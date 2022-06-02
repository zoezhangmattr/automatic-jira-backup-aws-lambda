#=======================================================================
# jira-backup lambda triggered by cw event
#=======================================================================
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = aws_iam_role.this.arn
  handler       = "backup.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  description   = var.function_name
  filename      = data.archive_file.lambda-handler.output_path
  layers = [
    aws_lambda_layer_version.requests.arn
  ]
  # reserved_concurrent_executions = 1
  environment {
    variables = merge({
      SSM_PREFIX     = var.ssm_prefix_path
      SLACK_CHANNEL  = var.slack_channel
      SLACK_USERNAME = var.slack_username
      BACKUP_S3      = var.s3_bucket_name
    }, var.extra_env_vars)
  }
}

resource "random_uuid" "lambda-src-hash" {
  keepers = {
    for filename in setunion(
      fileset("${path.module}/../", "backup.py"),
    ) :
    filename => filemd5("${path.module}/../${filename}")
  }
}
data "archive_file" "lambda-handler" {
  type        = "zip"
  source_file  = "${path.module}/../backup.py"
  output_path = "${path.module}/${random_uuid.lambda-src-hash.result}.zip"
}
output "lambda_file_name" {
  value = data.archive_file.lambda-handler.output_path
}
#============= python requests package layer =========================
resource "aws_lambda_layer_version" "requests" {
  filename   = data.archive_file.layer.output_path
  layer_name = "python_requests"

  description = "python requests package 2.27.1"

  compatible_runtimes = [var.lambda_runtime]

  compatible_architectures = ["x86_64"]
}

resource "random_uuid" "layer-hash" {
  keepers = {
    for filename in setunion(
      fileset("${path.module}/layer/", "*"),
    ) :
    filename => filemd5("${path.module}/layer/${filename}")
  }
}
data "archive_file" "layer" {
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/${random_uuid.layer-hash.result}.zip"
}
output "layer_file_name" {
  value = data.archive_file.layer.output_path
}
#============= kms key to encrypt parameter store =====================
data "aws_kms_alias" "this" {
  name = "alias/aws/ssm"
}
#============= lmabda role and policy =====================

resource "aws_iam_role" "this" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda-assume-role-policy.json

}

data "aws_iam_policy_document" "lambda-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role_policy_attachment" "asssume-role-policy-managed" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
}
resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.lambda-policy.arn
}

resource "aws_iam_policy" "lambda-policy" {
  name   = "${var.function_name}-role-policy"
  path   = "/"
  policy = data.aws_iam_policy_document.lambda-role-policy.json
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "lambda-role-policy" {
  statement {
    sid = "kmsdecrypt"
    actions = [
      "kms:Decrypt"
    ]
    resources = [
      data.aws_kms_alias.this.target_key_arn
    ]
  }
  statement {
    sid = "getssm"
    actions = [
      "ssm:GetParameter"
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_prefix_path}/*"
    ]
  }
  statement {
    sid = "uploads3"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket_name}/*"
    ]
  }
}
#============= cw schedule event ===================
resource "aws_cloudwatch_event_rule" "this" {
  name                = "jira-backup-schedule"
  description         = "the schedule to do jira backup"
  schedule_expression = var.schedule_expression
  is_enabled          = true
}
resource "aws_cloudwatch_event_target" "this" {
  arn  = aws_lambda_function.this.arn
  rule = aws_cloudwatch_event_rule.this.id
}
#============= lmabda permission :allow events =====================
resource "aws_lambda_permission" "this" {
  statement_id  = "AllowExecutionFromEvent"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this.arn
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name          = aws_lambda_function.this.function_name
  maximum_retry_attempts = 0
}
