provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    application = "inverse-optimization-app"
    managed_by  = "terraform"
  }
}
