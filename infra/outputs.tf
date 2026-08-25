output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "Default Google Cloud region"
  value       = var.region
}

output "enabled_services" {
  description = "APIs managed by this Terraform configuration"
  value       = sort([for service in google_project_service.required : service.service])
}
