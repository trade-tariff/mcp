data "aws_caller_identity" "current" {}

data "aws_vpc" "vpc" {
  tags = { Name = "trade-tariff-${var.environment}-vpc" }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Name = "*private*"
  }
}

data "aws_lb_target_group" "this_https" {
  name = "mcp-https"
}

data "aws_security_group" "this" {
  name = "trade-tariff-ecs-security-group-${var.environment}"
}

data "aws_kms_key" "this" {
  key_id = "alias/secretsmanager-key"
}

data "aws_secretsmanager_secret" "this" {
  name = "mcp-configuration"
}

data "aws_secretsmanager_secret_version" "this" {
  secret_id = data.aws_secretsmanager_secret.this.id
}

data "aws_secretsmanager_secret" "ecs_tls_certificate" {
  name = "ecs-tls-certificate"
}

data "aws_secretsmanager_secret_version" "ecs_tls_certificate" {
  secret_id = data.aws_secretsmanager_secret.ecs_tls_certificate.id
}

data "aws_secretsmanager_secret" "valkey_frontend" {
  name = "valkey-frontend-connection-string"
}

data "aws_secretsmanager_secret_version" "valkey_frontend" {
  secret_id = data.aws_secretsmanager_secret.valkey_frontend.id
}

data "aws_sns_topic" "slack_topic" {
  name = "slack-topic"
}

# The identity service creates the hub's API clients in its own Cognito
# pool, and that pool issues the bearer tokens that the MCP verifies. The
# pool ID comes from var.cognito_user_pool_id. It is not read from the
# identity-configuration secret, because a data source would copy the whole
# secret into this state. The deploy role can describe a pool, but it
# cannot list pools, so a lookup by name is not possible.
#
# Fails the plan if the ID does not name a real pool, or names the wrong one.
data "aws_cognito_user_pool" "identity" {
  user_pool_id = var.cognito_user_pool_id

  lifecycle {
    postcondition {
      condition     = self.name == "trade-tariff-identity-user-pool"
      error_message = "cognito_user_pool_id names the pool ${self.name}, not trade-tariff-identity-user-pool."
    }
  }
}
