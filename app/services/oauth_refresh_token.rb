# frozen_string_literal: true

# A refresh token is the client's own client_id + client_secret, encrypted
# and signed with a key derived from SECRET_KEY_BASE. Cognito does not give
# refresh tokens for client_credentials, so on refresh we decrypt this and
# exchange the credentials with Cognito again.
#
# The token is stateless: nothing is stored on the server. It expires after
# LIFETIME, and each refresh issues a new one. If the client is deleted in
# the hub, Cognito rejects the credentials, so revocation still works.
class OauthRefreshToken
  Credentials = Data.define(:client_id, :client_secret)

  LIFETIME = 30.days
  PURPOSE = "mcp_oauth_refresh_token"
  KEY_SALT = "mcp oauth refresh token"

  def self.issue(client_id:, client_secret:)
    encryptor.encrypt_and_sign({ "client_id" => client_id, "client_secret" => client_secret },
                               expires_in: LIFETIME, purpose: PURPOSE)
  end

  # Returns Credentials, or nil if the token was changed, has expired, or
  # was not issued by this server.
  def self.read(token)
    payload = encryptor.decrypt_and_verify(token, purpose: PURPOSE)
    return nil unless payload.is_a?(Hash)

    client_id = payload["client_id"]
    client_secret = payload["client_secret"]
    return nil if client_id.blank? || client_secret.blank?

    Credentials.new(client_id: client_id, client_secret: client_secret)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key(KEY_SALT, ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end
  private_class_method :encryptor
end
