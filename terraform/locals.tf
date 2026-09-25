locals {
  account_id     = data.aws_caller_identity.current.account_id
  has_autoscaler = var.environment != "development"

  tls_secret = jsondecode(data.aws_secretsmanager_secret_version.ecs_tls_certificate.secret_string)

  tls_env_vars = [
    {
      name  = "SSL_KEY_PEM"
      value = local.tls_secret.private_key
    },
    {
      name  = "SSL_CERT_PEM"
      value = local.tls_secret.certificate
    },
    {
      name  = "SSL_PORT"
      value = "8443"
    }
  ]

  secret_value = try(data.aws_secretsmanager_secret_version.this.secret_string, "{}")
  secret_map   = jsondecode(local.secret_value)
  # Terraform sets these keys itself, so a copy in the secret is ignored.
  # This stops two values from disagreeing.
  terraform_managed_env_var_names = ["COGNITO_USER_POOL_ID", "SECRET_KEY_BASE"]

  secret_env_vars = [
    for key, value in local.secret_map : {
      name  = key
      value = value
    } if !contains(local.terraform_managed_env_var_names, key)
  ]

  redis_env_var = [{
    name  = "REDIS_URL"
    value = data.aws_secretsmanager_secret_version.valkey_frontend.secret_string
  }]

  terraform_managed_env_vars = [
    {
      name  = "COGNITO_USER_POOL_ID"
      value = data.aws_cognito_user_pool.identity.user_pool_id
    },
    {
      name  = "SECRET_KEY_BASE"
      value = random_password.secret_key_base.result
    }
  ]

  service_env_vars = concat(local.secret_env_vars, local.tls_env_vars, local.redis_env_var, local.terraform_managed_env_vars)
}
