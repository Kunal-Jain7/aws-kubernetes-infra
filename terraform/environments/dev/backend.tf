terraform {
  backend "s3" {
    bucket = "terraform-kubernetes"
    key    = "terraform/dev/terraform.tfstate"
    region = "us-east-1"
  }
}
