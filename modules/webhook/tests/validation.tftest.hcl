mock_provider "aws" {}

variables {
  runner_matcher_config = {
    default = {
      arn = "arn:aws:sqs:eu-west-1:123456789012:runner"
      id  = "runner"
      matcherConfig = {
        labelMatchers = [["self-hosted", "linux"]]
        exactMatch    = true
      }
    }
  }

  github_app_parameters = {
    webhook_secret = {
      name = "/github/webhook"
      arn  = "arn:aws:ssm:eu-west-1:123456789012:parameter/github/webhook"
    }
  }

  ssm_paths = {
    root    = "/github"
    webhook = "webhook"
  }

  eventbridge = {
    enable = false
  }
}

run "reject_invalid_source_cidr" {
  command = plan

  variables {
    webhook_allowed_source_cidrs = ["192.30.252.0/33"]
  }

  expect_failures = [var.webhook_allowed_source_cidrs]
}
