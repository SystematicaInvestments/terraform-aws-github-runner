mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  distribution_bucket_name  = "runner-binaries-test"
  lambda_subnet_ids         = ["subnet-12345678"]
  lambda_security_group_ids = ["sg-12345678"]
  lambda_s3_bucket          = "lambda-bucket"
  syncer_lambda_s3_key      = "runner-binaries-syncer.zip"
  restricted_github         = true
}

run "plan_restricted" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_lambda_function.syncer.vpc_config) == 0,
      length(aws_iam_role_policy_attachment.syncer_vpc_execution_role) == 0,
    ])
    error_message = "Restricted mode should omit syncer VPC placement and permissions"
  }
}

run "plan_with_vpc" {
  command = plan

  variables {
    restricted_github = false
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.syncer.vpc_config) == 1,
      length(aws_iam_role_policy_attachment.syncer_vpc_execution_role) == 1,
    ])
    error_message = "Unrestricted mode should preserve syncer VPC placement and permissions"
  }
}

run "plan_with_partial_vpc_configuration" {
  command = plan

  variables {
    lambda_security_group_ids = []
    restricted_github         = false
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.syncer.vpc_config) == 0,
      length(aws_iam_role_policy_attachment.syncer_vpc_execution_role) == 0,
    ])
    error_message = "Partial VPC configuration should not place the syncer in a VPC or grant ENI permissions"
  }
}
