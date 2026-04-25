terraform {
  backend "s3" {
    bucket = "terraform-kubernetes"
    key    = "terraform/prod/terraform.tfstate"
    region = "eu-west-1"
  }
}
