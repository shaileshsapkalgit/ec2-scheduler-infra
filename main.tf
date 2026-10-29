locals {
  name = "${var.project_name}-${var.environment}"
}

# ---------- SNS topic and email subscription ----------

resource "aws_sns_topic" "report" {
  name = "${local.name}-report"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.report.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ---------- CloudWatch log group ----------

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}


# ---------- IAM role for the Lambda ----------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  # Reading is allowed on all instances. DescribeInstances cannot be limited by tag.
  statement {
    sid       = "DescribeInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # Start and stop only instances that carry the Schedule tag.
  statement {
    sid       = "StartStopTaggedInstances"
    effect    = "Allow"
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${var.schedule_tag_key}"
      values   = [var.schedule_tag_value]
    }
  }

  # Publish only to our report topic.
  statement {
    sid       = "PublishReport"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.report.arn]
  }

  # Write logs only to our log group.
  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "permissions"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ---------- Placeholder code (only for the first apply) ----------

data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/build/placeholder.zip"

  source {
    filename = "handler.py"
    content  = <<-EOT
      def handler(event, context):
          return {"message": "placeholder - real code is deployed by the app pipeline"}
    EOT
  }
}

# ---------- Lambda function ----------

resource "aws_lambda_function" "scheduler" {
  function_name = local.name
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  architectures = ["arm64"]
  memory_size   = 128
  timeout       = 60

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  # Publish a version only on the first create. Later versions come from the app pipeline.
  publish = true

  environment {
    variables = {
      SNS_TOPIC_ARN      = aws_sns_topic.report.arn
      SCHEDULE_TAG_KEY   = var.schedule_tag_key
      SCHEDULE_TAG_VALUE = var.schedule_tag_value
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]

  lifecycle {
    ignore_changes = [filename, source_code_hash, s3_bucket, s3_key, s3_object_version, publish, version, qualified_arn, qualified_invoke_arn, last_modified]
  }
}

# ---------- Alias "live" ----------

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.scheduler.function_name
  function_version = aws_lambda_function.scheduler.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

# ---------- Role used by EventBridge Scheduler ----------

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_permissions" {
  statement {
    sid     = "InvokeSchedulerLambda"
    effect  = "Allow"
    actions = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.scheduler.arn,
      "${aws_lambda_function.scheduler.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "invoke-lambda"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_permissions.json
}

# ---------- Two schedules ----------

resource "aws_scheduler_schedule" "stop" {
  name                         = "${local.name}-stop"
  description                  = "Stop office-hours EC2 instances at 8 PM IST, Monday to Friday"
  schedule_expression          = "cron(0 20 ? * MON-FRI *)"
  schedule_expression_timezone = "Asia/Kolkata"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "stop" })
  }

  depends_on = [aws_iam_role_policy.scheduler]
}

resource "aws_scheduler_schedule" "start" {
  name                         = "${local.name}-start"
  description                  = "Start office-hours EC2 instances at 9 AM IST, Monday to Friday"
  schedule_expression          = "cron(0 9 ? * MON-FRI *)"
  schedule_expression_timezone = "Asia/Kolkata"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_alias.live.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "start" })
  }

  depends_on = [aws_iam_role_policy.scheduler]
}