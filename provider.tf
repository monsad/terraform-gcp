provider "google" {
  project = "tetris-412514"
  region  = "us-central1"
  
 
}

terraform {
  required_providers {
    google = {
      version = "~> 3.83.0"
      source = "hashicorp/google"
    }
  }
}





terraform {
  backend "gcs" {
    bucket = "monika-tetis"
    prefix = "terraform/state"
    
  }
}



