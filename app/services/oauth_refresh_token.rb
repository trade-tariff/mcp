# frozen_string_literal: true

# A refresh token is the client's client_id, encrypted and signed with a key
# derived from SECRET_KEY_BASE. Cognito does not give refresh tokens for
# client_credentials, so on refresh the client sends its client_secret again
# and we exchange the credentials with Cognito again.
#
# The token does not hold the client_secret. A token without the secret
# cannot get an access token, so a leaked token is not a credential.
#
# The token is stateless: nothing is stored on the server. It expires after
# LIFETIME, and each refresh issues a new one. If the client is deleted in
# the hub, Cognito rejects the credentials, so revocation still works.
class OauthRefreshToken
  LIFETIME = 30.days
  PURPOSE = "mcp_oauth_refresh_token"
  KEY_SALT = "mcp oauth refresh token"

  def self.issue(client_id:)
    encryptor.encrypt_and_sign({ "client_id" => client_id }, expires_in: LIFETIME, purpose: PURPOSE)
  end

  # Returns the client_id, or nil if the token was changed, has expired, or
  # was not issued by this server.
  def self.read(token)
    payload = encryptor.decrypt_and_verify(token, purpose: PURPOSE)
    return nil unless payload.is_a?(Hash)

    client_id = payload["client_id"]
    return nil if client_id.blank?

    client_id
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key(KEY_SALT, ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end
  private_class_method :encryptor
end
