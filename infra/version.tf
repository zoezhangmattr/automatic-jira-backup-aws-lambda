terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.8"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~>2.2.0"
    }

  }
  required_version = "1.1.7"
}

