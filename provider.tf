provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ec2-scheduler"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}