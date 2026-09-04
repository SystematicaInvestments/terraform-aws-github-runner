mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
    }
  }
}

variables {
  aws_region = "eu-west-1"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-12345678"]

  lambda_subnet_ids         = ["subnet-lambda-12345678"]
  lambda_security_group_ids = ["sg-lambda-12345678"]

  instance_types = ["m5.large"]

  s3_runner_binaries = {
    arn = "arn:aws:s3:::my-bucket"
    id  = "my-bucket"
    key = "runners/linux/actions-runner.tar.gz"
  }

  sqs_build_queue = {
    arn = "arn:aws:sqs:eu-west-1:123456789012:build-queue"
    url = "https://sqs.eu-west-1.amazonaws.com/123456789012/build-queue"
  }

  enable_organization_runners = true
  enable_ssm_on_runners       = true
  runner_labels               = ["self-hosted", "linux", "x64"]
  http_proxy                  = "http://proxy.example.com:8080"
  no_proxy                    = "169.254.169.254,amazonaws.com"
  restricted_github           = true

  # Use S3 bucket to avoid filebase64sha256 needing local zip files
  lambda_s3_bucket      = "my-lambda-bucket"
  runners_lambda_s3_key = "runners.zip"

  github_app_parameters = {
    key_base64      = [{ name = "/github-runner/key-base64", arn = "arn:aws:ssm:eu-west-1:123456789012:parameter/github-runner/key-base64" }]
    id              = [{ name = "/github-runner/app-id", arn = "arn:aws:ssm:eu-west-1:123456789012:parameter/github-runner/app-id" }]
    installation_id = [null]
  }

  ssm_paths = {
    root   = "/github-runner"
    tokens = "tokens"
    config = "config"
  }

  # Enable pool to exercise the pool module and its role type
  pool_config = [{
    schedule_expression = "cron(0 8 * * ? *)"
    size                = 1
  }]
}

run "plan_with_pool_enabled" {
  command = plan

  assert {
    condition     = length(module.pool) == 1
    error_message = "Pool module should be enabled when pool_config is non-empty"
  }

  assert {
    condition = alltrue([
      aws_lambda_function.scale_up.environment[0].variables["HTTP_PROXY"] == var.http_proxy,
      aws_lambda_function.scale_up.environment[0].variables["HTTPS_PROXY"] == var.http_proxy,
      aws_lambda_function.scale_up.environment[0].variables["http_proxy"] == var.http_proxy,
      aws_lambda_function.scale_up.environment[0].variables["https_proxy"] == var.http_proxy,
      aws_lambda_function.scale_up.environment[0].variables["NO_PROXY"] == var.no_proxy,
      aws_lambda_function.scale_up.environment[0].variables["no_proxy"] == var.no_proxy,
      aws_lambda_function.scale_up.environment[0].variables["NODE_USE_ENV_PROXY"] == "1",
      aws_lambda_function.scale_up.environment[0].variables["NODE_EXTRA_CA_CERTS"] == "/opt/barracuda_ca.crt",
    ])
    error_message = "Scale-up Lambda should receive the complete proxy environment"
  }

  assert {
    condition = alltrue([
      aws_lambda_function.scale_down.environment[0].variables["HTTP_PROXY"] == var.http_proxy,
      aws_lambda_function.scale_down.environment[0].variables["NO_PROXY"] == var.no_proxy,
      aws_lambda_function.scale_down.environment[0].variables["NODE_USE_ENV_PROXY"] == "1",
      aws_lambda_function.scale_down.environment[0].variables["NODE_EXTRA_CA_CERTS"] == "/opt/barracuda_ca.crt",
    ])
    error_message = "Scale-down Lambda should receive the proxy and CA environment"
  }

  assert {
    condition = alltrue([
      length(aws_lambda_layer_version.barracuda_ca) == 1,
      length(aws_lambda_function.scale_up.layers) == 1,
      length(aws_lambda_function.scale_down.layers) == 1,
    ])
    error_message = "Proxy-enabled Lambdas should attach the Barracuda CA layer"
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.ssm_housekeeper.vpc_config) == 0,
      length(aws_iam_role_policy_attachment.ssm_housekeeper_vpc_execution_role) == 0,
    ])
    error_message = "Restricted GitHub mode should keep the SSM housekeeper outside the VPC"
  }

  assert {
    condition = alltrue([
      startswith(local.user_data, "#!/bin/bash -e"),
      strcontains(local.user_data, "sudo --preserve-env=RUNNER_ALLOW_RUNASROOT,HTTP_PROXY,HTTPS_PROXY,http_proxy,https_proxy,NO_PROXY,no_proxy,NODE_EXTRA_CA_CERTS"),
      strcontains(local.user_data, "if [[ -f \"/opt/github.runner.service.template\" ]]"),
    ])
    error_message = "Runner user data should fail fast and preserve only the required runner environment"
  }
}

run "plan_with_vpc_enabled" {
  command = plan

  variables {
    restricted_github = false
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.scale_up.vpc_config) == 1,
      length(aws_lambda_function.scale_down.vpc_config) == 1,
      length(aws_lambda_function.ssm_housekeeper.vpc_config) == 1,
      length(aws_iam_role_policy_attachment.ssm_housekeeper_vpc_execution_role) == 1,
    ])
    error_message = "Unrestricted mode should preserve configured Lambda VPC placement and permissions"
  }
}

run "plan_without_proxy" {
  command = plan

  variables {
    http_proxy = null
    no_proxy   = null
  }

  assert {
    condition = alltrue([
      length(aws_lambda_layer_version.barracuda_ca) == 0,
      length(aws_lambda_function.scale_up.layers) == 0,
      length(aws_lambda_function.scale_down.layers) == 0,
      aws_lambda_function.scale_up.environment[0].variables["HTTP_PROXY"] == "",
      aws_lambda_function.scale_up.environment[0].variables["NODE_USE_ENV_PROXY"] == "0",
    ])
    error_message = "The default configuration should not attach or enable the proxy CA layer"
  }
}

run "plan_with_partial_vpc_configuration" {
  command = plan

  variables {
    restricted_github         = false
    lambda_security_group_ids = []
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.scale_up.vpc_config) == 0,
      length(aws_lambda_function.scale_down.vpc_config) == 0,
      length(aws_lambda_function.ssm_housekeeper.vpc_config) == 0,
      length(aws_iam_role_policy_attachment.scale_up_vpc_execution_role) == 0,
      length(aws_iam_role_policy_attachment.scale_down_vpc_execution_role) == 0,
      length(aws_iam_role_policy_attachment.ssm_housekeeper_vpc_execution_role) == 0,
    ])
    error_message = "Partial VPC configuration should not place Lambdas in a VPC or grant ENI permissions"
  }
}

run "reject_proxy_credentials" {
  command = plan

  variables {
    http_proxy = "http://user:secret@proxy.example.com:8080"
  }

  expect_failures = [var.http_proxy]
}
