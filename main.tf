terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}



provider "google" {
  credentials = file(var.gcp_credentials)
  project     = var.gcp_projectid
  region      = var.gcp_region
  zone        = var.gcp_zone
}



resource "google_compute_instance" "vm_instance" {
  project      = var.gcp_projectid
  zone         = var.gcp_zone
  name         = "terraform-instance"
  machine_type = "e2-medium"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    # A default network is created for all GCP projects
    network    = google_compute_network.tf_network.self_link
    subnetwork = google_compute_subnetwork.tf_subnet.self_link
  }

  metadata_startup_script = data.template_file.startup_script.rendered

}


resource "google_compute_network" "tf_network" {
  name                    = "tf-network"
  project                 = var.gcp_projectid
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"
  #delete_default_routes_on_create = true

}
resource "google_compute_subnetwork" "tf_subnet" {
  name                     = "tf-subnetwork"
  network                  = google_compute_network.tf_network.id
  ip_cidr_range            = "10.0.0.0/24"
  region                   = var.gcp_region
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.0.1.0/24"
  }

  secondary_ip_range {
    range_name    = "pod-ranges"
    ip_cidr_range = "10.0.2.0/24"
  }
}
resource "google_compute_router" "tf_router" {
  name    = "tf-router"
  region  = google_compute_subnetwork.tf_subnet.region
  network = google_compute_network.tf_network.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "tf_nat" {
  name                               = "tf-router-nat"
  router                             = google_compute_router.tf_router.name
  region                             = google_compute_router.tf_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = false
    filter = "ERRORS_ONLY"
  }
}


resource "google_compute_firewall" "default" {
  project = var.gcp_projectid
  name    = "tf-allow-ssh"
  network = google_compute_network.tf_network.name

  allow {
    protocol = "tcp"
    ports    = ["80", "8080", "22"]
  }
  source_ranges = ["35.235.240.0/20"]
}


resource "google_compute_firewall" "health_check_allow" {
  project = var.gcp_projectid
  name    = "tf-allow-health-check"
  network = google_compute_network.tf_network.name

  allow {
    protocol = "tcp"
    ports    = ["10256"]
  }
  source_ranges = [google_compute_subnetwork.tf_subnet.ip_cidr_range]
}

output "internal-ip-address" {
  value = google_compute_instance.vm_instance.network_interface.0.network_ip
}

# output "external-ip-address" {

#     value = google_compute_instance.vm_instance.network_interface.0.access_config.0.nat_ip
# }

data "template_file" "startup_script" {
  template = <<-EOF
  sudo apt-get update -y
  sudo apt-get install apt-transport-https ca-certificates gnupg -y
  sudo apt-get install kubectl -y
  sudo apt-get install google-cloud-sdk-gke-gcloud-auth-plugin -y
  EOF
}
#################################################################### GKE Cluster 
# enable Identity and Access Management (IAM) API
# enable Compute Engine API 
# enable Kubernetes Engine API 





resource "google_container_cluster" "tf_cluster" {
  name               = "tf-cluster"
  location           = var.gcp_zone
  initial_node_count = 1

  network    = google_compute_network.tf_network.id
  subnetwork = google_compute_subnetwork.tf_subnet.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "services-range"
    services_secondary_range_name = google_compute_subnetwork.tf_subnet.secondary_ip_range.1.range_name
  }


  # private_cluster_config {
  #   enable_private_nodes =true
  #   enable_private_endpoint = true
  #   master_ipv4_cidr_block = "192.168.1.0/24"
  #   master_global_access_config {
  #     enabled = true
  #   }
  # }

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  # remove_default_node_pool = true
  remove_default_node_pool = true
  master_auth {
    username = ""
    password = ""
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # here i can specify the control node cidr range
  # master_authorized_networks_config {
  #   cidr_blocks {
  #     cidr_block   = "10.0.0.0/24"
  #     display_name = "any"
  #   }
  # }

  addons_config {
    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }
  }
  # other settings...
}



resource "google_container_node_pool" "tf_node_pool" {
  name = "tf-node-pool"
  # location = var.gcp_region
  cluster = google_container_cluster.tf_cluster.name
  depends_on = [
    google_container_cluster.tf_cluster
  ]
  node_count = 1
  # management {
  #   auto_repair = true
  # }
  node_config {
    preemptible  = true
    machine_type = "e2-medium"


    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring"
    ]
  }
}

