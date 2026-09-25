# frozen_string_literal: true

# Verifies that a bearer token is a genuine Cognito access token for the
# Trade Tariff identity pool, with the tariff/read scope.
#
# /token exchanges a client_id + client_secret with Cognito for this token,
# so a token that passes here proves the caller holds valid credentials.
# These are the same checks the API gateway authorizer lambda makes.
#
# Returns a Result instead of raising, so the caller decides the response:
#   :valid       - the token verified; client_id is set
#   :invalid     - the token is not genuine, has expired, or lacks the scope
#   :unavailable - the pool's signing keys could not be fetched
class CognitoTokenVerifier
  Result = Data.define(:status, :client_id)

  REQUIRED_SCOPE = "tariff/read"
  JWKS_CACHE_KEY = "cognito_token_verifier:jwks"
  JWKS_CACHE_TTL = 1.hour
  # Cognito rotates signing keys rarely. Refetching on every unknown kid would
  # let anyone force a JWKS request per call, so only refetch a cached copy
  # that is at least this old.
  JWKS_MIN_REFETCH_INTERVAL = 5.minutes

  INVALID = Result.new(status: :invalid, client_id: nil)
  UNAVAILABLE = Result.new(status: :unavailable, client_id: nil)

  class JwksUnavailable < StandardError; end

  def initialize(user_pool_id:, region:)
    @issuer = "https://cognito-idp.#{region}.amazonaws.com/#{user_pool_id}"
    @jwks_url = "#{@issuer}/.well-known/jwks.json"
  end

  def verify(token)
    claims, _header = JWT.decode(token, nil, true,
                                 algorithms: [ "RS256" ],
                                 jwks: method(:load_jwks),
                                 iss: @issuer,
                                 verify_iss: true,
                                 required_claims: [ "exp", "token_use" ])

    return INVALID unless claims["token_use"] == "access"
    return INVALID unless claims["scope"].to_s.split(" ").include?(REQUIRED_SCOPE)

    Result.new(status: :valid, client_id: claims["client_id"] || claims["sub"])
  rescue JwksUnavailable
    UNAVAILABLE
  rescue JWT::DecodeError => e
    Rails.logger.info("Rejected bearer token: #{e.class}")
    INVALID
  end

  private

  # Called by JWT.decode. options[:kid_not_found] is set when the token's kid
  # is not in the keys we returned last time, which is how key rotation shows.
  def load_jwks(options)
    cached = Rails.cache.read(JWKS_CACHE_KEY)
    fetched_long_enough_ago = cached && cached["fetched_at"] <= JWKS_MIN_REFETCH_INTERVAL.ago.to_i
    return cached["jwks"] if cached && !(options[:kid_not_found] && fetched_long_enough_ago)

    jwks = fetch_jwks
    if jwks.nil?
      # Keep verifying with the old keys if a rotation refetch fails.
      return cached["jwks"] if cached

      raise JwksUnavailable
    end

    Rails.cache.write(JWKS_CACHE_KEY, { "jwks" => jwks, "fetched_at" => Time.current.to_i }, expires_in: JWKS_CACHE_TTL)
    jwks
  end

  def fetch_jwks
    response = Faraday.get(@jwks_url) do |request|
      request.options.open_timeout = 2
      request.options.timeout = 5
    end

    unless response.status == 200
      Rails.logger.warn("Cognito JWKS fetch failed: status=#{response.status}")
      return nil
    end

    JSON.parse(response.body)
  rescue Faraday::Error => e
    Rails.logger.warn("Cognito JWKS fetch error: #{e.class} #{e.message}")
    nil
  rescue JSON::ParserError => e
    Rails.logger.warn("Cognito JWKS unparseable response: #{e.message}")
    nil
  end
end
