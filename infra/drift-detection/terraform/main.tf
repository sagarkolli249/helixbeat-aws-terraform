###############################################################################
# HelixBeat – Drift Detection Infrastructure
# Slide 4: EventBridge → Lambda → CodeBuild (terraform plan) → SNS → Teams/PagerDuty
###############################################################################

locals {
  name_prefix = "helixbeat-drift"
}

# ── IAM role for Lambda ────────────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "drift_lambda" {
  name               = "${local.name_prefix}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.drift_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "drift_lambda_perms" {
  name = "${local.name_prefix}-perms"
  role = aws_iam_role.drift_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = aws_codebuild_project.drift.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.drift_alerts.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.drift_s3_bucket_arn}/drift/*"
      },
    ]
  })
}

# ── Lambda function ────────────────────────────────────────────────────────────
data "archive_file" "drift_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "/tmp/drift-lambda.zip"
}

resource "aws_lambda_function" "drift" {
  function_name    = "${local.name_prefix}-trigger"
  role             = aws_iam_role.drift_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.drift_lambda.output_path
  source_code_hash = data.archive_file.drift_lambda.output_base64sha256

  environment {
    variables = {
      CODEBUILD_PROJECT_NAME = aws_codebuild_project.drift.name
      SNS_TOPIC_ARN          = aws_sns_topic.drift_alerts.arn
      S3_DRIFT_BUCKET        = var.drift_s3_bucket_name
      ENVIRONMENTS           = join(",", var.environments)
      GITHUB_ORG             = var.github_org
    }
  }

  tags = var.tags
}

# ── EventBridge rule (daily 06:00 UTC) ────────────────────────────────────────
resource "aws_cloudwatch_event_rule" "daily_drift_check" {
  name                = "${local.name_prefix}-daily"
  description         = "Daily Terraform drift detection across all environments"
  schedule_expression = "cron(0 6 * * ? *)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "drift_lambda" {
  rule = aws_cloudwatch_event_rule.daily_drift_check.name
  arn  = aws_lambda_function.drift.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drift.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_drift_check.arn
}

# ── EventBridge rule for CodeBuild completion ─────────────────────────────────
resource "aws_cloudwatch_event_rule" "codebuild_complete" {
  name        = "${local.name_prefix}-codebuild-complete"
  description = "Handle CodeBuild drift check completion"
  event_pattern = jsonencode({
    source      = ["aws.codebuild"]
    detail-type = ["CodeBuild Build State Change"]
    detail = {
      "project-name" = [aws_codebuild_project.drift.name]
      "build-status" = ["SUCCEEDED", "FAILED"]
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "drift_result_lambda" {
  rule = aws_cloudwatch_event_rule.codebuild_complete.name
  arn  = aws_lambda_function.drift.arn
  input_transformer {
    input_paths    = { "detail" = "$.detail" }
    input_template = "{\"detail\": <detail>}"
  }
}

# ── SNS topic for drift alerts ────────────────────────────────────────────────
resource "aws_sns_topic" "drift_alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = var.kms_key_id
  tags              = var.tags
}

# Teams webhook subscription via Lambda (or use a pre-existing subscription)
resource "aws_sns_topic_subscription" "teams_email" {
  topic_arn = aws_sns_topic.drift_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CodeBuild project (runs terraform plan) ────────────────────────────────────
resource "aws_iam_role" "codebuild" {
  name               = "${local.name_prefix}-codebuild"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild_perms" {
  name = "${local.name_prefix}-codebuild-perms"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [var.tfstate_bucket_arn, "${var.tfstate_bucket_arn}/*", "${var.drift_s3_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = var.tfstate_lock_table_arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      # Add terraform resource read permissions as needed per environment
      { Effect = "Allow", Action = "sts:AssumeRole", Resource = var.tf_execution_role_arn },
    ]
  })
}

resource "aws_codebuild_project" "drift" {
  name          = "${local.name_prefix}-plan"
  description   = "Runs terraform plan to detect infrastructure drift"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "hashicorp/terraform:1.7"
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TF_ENV"
      value = "dev-us"  # overridden per build
    }
    environment_variable {
      name  = "ACTION"
      value = "drift-check"
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_org}/helixbeat-infra"
    git_clone_depth = 1
    buildspec       = <<-BUILDSPEC
      version: 0.2
      phases:
        install:
          commands:
            - terraform --version
        build:
          commands:
            - cd terraform/environments/$TF_ENV
            - terraform init -reconfigure
            - terraform plan -detailed-exitcode -input=false 2>&1 | tee /tmp/drift-plan.txt
            - EXIT_CODE=${PIPESTATUS[0]}
            - |
              if [ "$EXIT_CODE" = "2" ]; then
                aws s3 cp /tmp/drift-plan.txt \
                  s3://$S3_DRIFT_BUCKET/drift/$TF_ENV/$(date +%Y-%m-%d)-drift.txt \
                  --sse aws:kms
                echo "DRIFT DETECTED in $TF_ENV"
                exit 1
              elif [ "$EXIT_CODE" = "0" ]; then
                echo "No drift in $TF_ENV"
              else
                echo "Terraform plan errored"
                exit $EXIT_CODE
              fi
      BUILDSPEC
  }

  tags = var.tags
}
