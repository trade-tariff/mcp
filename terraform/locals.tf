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
  # These keys do not go into the task as plain environment variables.
  # Terraform sets COGNITO_USER_POOL_ID itself, so a copy in the secret is
  # ignored and two values cannot disagree. SECRET_KEY_BASE goes into the
  # task through service_secrets below, so its value does not show on the
  # task definition.
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
    }
  ]

  service_env_vars = concat(local.secret_env_vars, local.tls_env_vars, local.redis_env_var, local.terraform_managed_env_vars)

  # ECS reads these from Secrets Manager when a task starts. The task
  # definition holds only the ARN and key, not the value.
  #
  # SECRET_KEY_BASE is the Rails secret_key_base. OAuth refresh tokens are
  # encrypted with a key derived from it, so it must be the same on every
  # task and stay the same across deploys. Changing it in the secret makes
  # all refresh tokens invalid, and every user must connect again.
  service_secrets = [
    {
      name      = "SECRET_KEY_BASE"
      valueFrom = "${data.aws_secretsmanager_secret.this.arn}:SECRET_KEY_BASE::"
    }
  ]
}
