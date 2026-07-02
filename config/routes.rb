Rails.application.routes.draw do
  get "healthcheckz" => "rails/health#show", as: :rails_health_check

  get ".well-known/oauth-protected-resource" => "oauth#protected_resource"
  get ".well-known/oauth-authorization-server" => "oauth#metadata"
  get "authorize" => "oauth#authorize"
  post "token" => "oauth#token"
  post "oauth/register" => "oauth#register"

  mount ->(env) { Rails.application.config.mcp_transport.call(env) }, at: "/"
end
