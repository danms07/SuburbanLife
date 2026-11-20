terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 8.0.0, < 9.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.12.0, < 1.0.0"
    }
  }
}
