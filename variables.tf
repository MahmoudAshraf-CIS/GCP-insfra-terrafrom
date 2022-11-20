variable "gcp_credentials" {
    type = string
    description = "location for the GCP service account key - generated from the service account"
  
}

variable "gcp_projectid" {
    type = string
    description = "GCP projecy id"
  
}
variable "gcp_region" {
    type = string
    description = "region to deploy over GCP"
}

variable "gcp_zone" {
    type = string
    description = "gcp zone"
}

variable "gcp_gke_locations" {
    type = list(string)
    description = "the location where the cluster will be holding the worker nodes"
}