mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  config = {
    prefix                       = "test-eventbridge"
    lambda_s3_bucket             = "lambda-bucket"
    lambda_s3_key                = "webhook.zip"
    sqs_job_queues_arns          = ["arn:aws:sqs:eu-west-1:123456789012:runner"]
    api_gw_source_arn            = "arn:aws:execute-api:eu-west-1:123456789012:test/*"
    github_app_parameters        = { webhook_secret = { name = "/github/webhook", arn = "arn:aws:ssm:eu-west-1:123456789012:parameter/github/webhook" } }
    webhook_allowed_source_cidrs = ["2a0a:a440::/29"]
    ssm_parameter_runner_matcher_config = [{
      name    = "/github/matcher"
      arn     = "arn:aws:ssm:eu-west-1:123456789012:parameter/github/matcher"
      version = "1"
    }]
  }
}

run "plan_without_vpc" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_lambda_function.webhook.vpc_config) == 0,
      length(aws_lambda_function.dispatcher.vpc_config) == 0,
      length(aws_iam_role_policy_attachment.webhook_vpc_execution_role) == 0,
      length(aws_iam_role_policy_attachment.dispatcher_vpc_execution_role) == 0,
      aws_lambda_function.webhook.environment[0].variables["WEBHOOK_ALLOWED_SOURCE_CIDRS"] == jsonencode(var.config.webhook_allowed_source_cidrs),
    ])
    error_message = "Empty network lists should omit EventBridge Lambda VPC placement and preserve the source allowlist"
  }
}

run "plan_with_vpc" {
  command = plan

  variables {
    config = {
      prefix                       = "test-eventbridge"
      lambda_subnet_ids            = ["subnet-12345678"]
      lambda_security_group_ids    = ["sg-12345678"]
      lambda_s3_bucket             = "lambda-bucket"
      lambda_s3_key                = "webhook.zip"
      sqs_job_queues_arns          = ["arn:aws:sqs:eu-west-1:123456789012:runner"]
      api_gw_source_arn            = "arn:aws:execute-api:eu-west-1:123456789012:test/*"
      github_app_parameters        = { webhook_secret = { name = "/github/webhook", arn = "arn:aws:ssm:eu-west-1:123456789012:parameter/github/webhook" } }
      webhook_allowed_source_cidrs = ["2a0a:a440::/29"]
      ssm_parameter_runner_matcher_config = [{
        name    = "/github/matcher"
        arn     = "arn:aws:ssm:eu-west-1:123456789012:parameter/github/matcher"
        version = "1"
      }]
    }
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.webhook.vpc_config) == 1,
      length(aws_lambda_function.dispatcher.vpc_config) == 1,
      length(aws_iam_role_policy_attachment.webhook_vpc_execution_role) == 1,
      length(aws_iam_role_policy_attachment.dispatcher_vpc_execution_role) == 1,
    ])
    error_message = "Configured network lists should preserve EventBridge Lambda VPC placement and permissions"
  }
}

run "plan_with_partial_vpc_configuration" {
  command = plan

  variables {
    config = {
      prefix                       = "test-eventbridge"
      lambda_subnet_ids            = ["subnet-12345678"]
      lambda_security_group_ids    = []
      lambda_s3_bucket             = "lambda-bucket"
      lambda_s3_key                = "webhook.zip"
      sqs_job_queues_arns          = ["arn:aws:sqs:eu-west-1:123456789012:runner"]
      api_gw_source_arn            = "arn:aws:execute-api:eu-west-1:123456789012:test/*"
      github_app_parameters        = { webhook_secret = { name = "/github/webhook", arn = "arn:aws:ssm:eu-west-1:123456789012:parameter/github/webhook" } }
      webhook_allowed_source_cidrs = ["2a0a:a440::/29"]
      ssm_parameter_runner_matcher_config = [{
        name    = "/github/matcher"
        arn     = "arn:aws:ssm:eu-west-1:123456789012:parameter/github/matcher"
        version = "1"
      }]
    }
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.webhook.vpc_config) == 0,
      length(aws_lambda_function.dispatcher.vpc_config) == 0,
      length(aws_iam_role_policy_attachment.webhook_vpc_execution_role) == 0,
      length(aws_iam_role_policy_attachment.dispatcher_vpc_execution_role) == 0,
    ])
    error_message = "Partial VPC configuration should not place EventBridge Lambdas in a VPC or grant ENI permissions"
  }
}
