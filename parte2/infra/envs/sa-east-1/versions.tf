terraform {
  required_version = ">= 1.10.0" # use_lockfile no backend S3 (sem DynamoDB)
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
