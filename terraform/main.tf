variable "token" {
  description = "Yandex Cloud security OAuth token"
}

variable "cloud_id" {
  description = "your cloud id"
}

variable "ssh_login" {
  description = "your ssh login"
}

variable "ssh_public_key" {
  description = "your ssh public key"
}

resource "yandex_resourcemanager_folder" "folder" {
  cloud_id    = "${var.cloud_id}"
  name        = "retail"
  description = "sale of goods and services"
}

resource "yandex_iam_service_account" "sa" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name = "gitlabrunner"
}

resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = yandex_resourcemanager_folder.folder.id
  role      = "admin"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
  depends_on = [
    yandex_iam_service_account.sa,
 ]
}

resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "static access key for object storage"
  depends_on = [
    yandex_iam_service_account.sa,
 ]
}

resource "yandex_storage_bucket" "bucket" {
  folder_id = yandex_resourcemanager_folder.folder.id
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket = "retail-bucket-ru-central1-a"
}

resource "yandex_vpc_network" "network" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name = yandex_resourcemanager_folder.folder.name
  description = "Main network for ${yandex_resourcemanager_folder.folder.name}"
}

resource "yandex_dns_zone" "zone1" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name        = "commerce-store-zone"
  description = "commerce-store public zone"
  zone    = "commerce-store.ru."
  public  = true
}

resource "yandex_vpc_subnet" "subnet" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name           = "${yandex_resourcemanager_folder.folder.name}-ru-central1-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.10.0/24"]
  depends_on = [
    yandex_vpc_network.network,
  ]
}

resource "yandex_kubernetes_cluster" "k8s" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name        = "k8s"
  description = "description"
  network_id = "${yandex_vpc_network.network.id}"
  master {
    version = "1.26"
    zonal {
      zone      = "${yandex_vpc_subnet.subnet.zone}"
      subnet_id = "${yandex_vpc_subnet.subnet.id}"
    }
    public_ip = true
    maintenance_policy {
      auto_upgrade = true
      maintenance_window {
        start_time = "05:00"
        duration   = "3h"
      }
    }
  }
  service_account_id      = "${yandex_iam_service_account.sa.id}"
  node_service_account_id = "${yandex_iam_service_account.sa.id}"
  release_channel = "STABLE"
  network_policy_provider = "CALICO"
  kms_provider {
    key_id = "${yandex_kms_symmetric_key.kms-key.id}"
  }
}

resource "yandex_kms_symmetric_key" "kms-key" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name              = "kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h"
}

resource "yandex_kubernetes_node_group" "workers" {
  cluster_id  = "${yandex_kubernetes_cluster.k8s.id}"
  name = "workers"
  version     = "1.26"
  instance_template {
    name        = "worker-{instance.index}"
    platform_id = "standard-v3"
    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.subnet.id}"]
    }
    resources {
      memory = 8
      cores  = 4
      core_fraction = 100
    }
    boot_disk {
      type = "network-hdd"
      size = 64
    }
    scheduling_policy {
      preemptible = true
    }
    container_runtime {
      type = "containerd"
    }
  }
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }
  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "2:00"
      duration   = "3h"
    }
    maintenance_window {
      day        = "friday"
      start_time = "2:00"
      duration   = "4h30m"
    }
  }
}



