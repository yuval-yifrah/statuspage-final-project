terraform {
  backend "s3" {
    bucket         = "lyterraformstate"   # change to your bucket name
    key            = "terraform.tfstate" # location of the file in the bucket
    region         = "us-east-1"            # region
  }
}

