terraform {
  backend "s3" {
    bucket         = "lyterraformstate"   # השם של הבאקט שפתחת ידנית
    key            = "terraform.tfstate.backup" # מיקום הקובץ בתוך הבאקט
    region         = "us-east-1"            # האזור של הבאקט
  }
}

