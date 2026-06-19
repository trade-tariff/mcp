data "aws_iam_policy_document" "task" {
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "task" {
  name   = "mcp-task-role-policy-${var.environment}"
  policy = data.aws_iam_policy_document.task.json
}

data "aws_iam_policy_document" "exec" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = [
      data.aws_secretsmanager_secret.this.arn,
      data.aws_secretsmanager_secret.valkey_frontend.arn,
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKeyWithoutPlaintext"
    ]
    resources = [data.aws_kms_key.this.arn]
  }
}

resource "aws_iam_policy" "exec" {
  name   = "mcp-exec-role-policy-${var.environment}"
  policy = data.aws_iam_policy_document.exec.json
}
