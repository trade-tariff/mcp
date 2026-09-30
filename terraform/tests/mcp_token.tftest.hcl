# The MCP token comes from mcp-shared-credentials, which the terraform repo
# (trade-tariff-platform-aws-terraform) generates. It must win over any stale
# MCP_SECRET_TOKEN still in the hand-filled mcp-configuration secret.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_secretsmanager_secret_version.this
    values = {
      secret_string = "{\"MCP_SECRET_TOKEN\":\"stale-token\",\"TARIFF_API_URL\":\"https://example.test\"}"
    }
  }

  override_data {
    target = data.aws_secretsmanager_secret_version.mcp_shared_credentials
    values = {
      secret_string = "{\"MCP_SECRET_TOKEN\":\"token-from-terraform\",\"MCP_USAGE_KEY\":\"usage-key\"}"
    }
  }

  override_data {
    target = data.aws_secretsmanager_secret_version.ecs_tls_certificate
    values = {
      secret_string = "{\"private_key\":\"key\",\"certificate\":\"cert\"}"
    }
  }

  override_data {
    target = data.aws_sns_topic.slack_topic
    values = {
      arn = "arn:aws:sns:eu-west-2:123456789012:slack-topic"
    }
  }

  override_data {
    target = data.aws_secretsmanager_secret_version.valkey_frontend
    values = {
      secret_string = "rediss://example.test:6379"
    }
  }
}

override_module {
  target = module.service
}

variables {
  environment = "development"
  region      = "eu-west-2"
  docker_tag  = "test"
}

run "token_comes_from_mcp_shared_credentials" {
  command = plan

  assert {
    condition = nonsensitive([
      for env_var in local.service_env_vars : env_var.value if env_var.name == "MCP_SECRET_TOKEN"
    ]) == ["token-from-terraform"]
    error_message = "MCP_SECRET_TOKEN must be set once, from mcp-shared-credentials."
  }

  assert {
    condition     = length([for env_var in local.service_env_vars : env_var if env_var.name == "MCP_USAGE_KEY"]) == 0
    error_message = "The MCP server does not use MCP_USAGE_KEY, so it must not get it."
  }

  assert {
    condition     = length([for env_var in local.service_env_vars : env_var if env_var.name == "TARIFF_API_URL"]) == 1
    error_message = "Other values from mcp-configuration must still be passed."
  }
}
