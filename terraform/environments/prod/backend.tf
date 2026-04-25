terraform {
  backend "s3" {
    bucket = "terraform-kubernetes-kunal"
    key    = "terraform/prod/terraform.tfstate"
    region = "eu-west-1"
  }
}
