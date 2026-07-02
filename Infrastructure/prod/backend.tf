terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "tf-devops-ai-statefile"
    key          = "devops-ai/prod/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true # S3-native state locking (no DynamoDB table needed)
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
