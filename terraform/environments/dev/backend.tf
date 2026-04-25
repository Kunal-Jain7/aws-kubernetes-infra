terraform {
  backend "s3" {
    bucket = "terraform-kubernetes-kunal"
    key    = "terraform/dev/terraform.tfstate"
    region = "us-east-1"
  }
}
