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
  role      = "editor"
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

resource "yandex_vpc_subnet" "subnet1" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name           = "${yandex_resourcemanager_folder.folder.name}-ru-central1-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.10.0/24"]
  depends_on = [
    yandex_vpc_network.network,
  ]
}

resource "yandex_vpc_subnet" "subnet2" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name           = "${yandex_resourcemanager_folder.folder.name}-ru-central1-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.20.0/24"]
  depends_on = [
    yandex_vpc_network.network,
  ]
}

resource "yandex_vpc_subnet" "subnet3" {
  folder_id = yandex_resourcemanager_folder.folder.id
  name           = "${yandex_resourcemanager_folder.folder.name}-ru-central1-c"
  zone           = "ru-central1-c"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.0.30.0/24"]
  depends_on = [
    yandex_vpc_network.network,
  ]
}

data template_file "userdata" {
  template = file("./userdata.yaml")
  vars = {
    username           = var.ssh_login
    ssh_public_key     = var.ssh_public_key
  }
}

resource "yandex_compute_instance_group" "masters" {
  name               = "kubernetes-masters"
  folder_id = yandex_resourcemanager_folder.folder.id
  service_account_id = yandex_iam_service_account.sa.id
  depends_on = [
    yandex_iam_service_account.sa,
    yandex_resourcemanager_folder_iam_member.sa-editor,
    yandex_vpc_network.network,
    yandex_vpc_subnet.subnet1,
    yandex_vpc_subnet.subnet2,
    yandex_vpc_subnet.subnet3,
  ]
  
  # Шаблон экземпляра, к которому принадлежит группа экземпляров.
  instance_template {

    # Имя виртуальных машин, создаваемых Instance Groups
    name = "master-{instance.index}"
    # Ресурсы, которые будут выделены для создания виртуальных машин в Instance Groups
    resources {
      cores  = 2
      memory = 2
      core_fraction = 100 # Базовый уровень производительности vCPU. https://cloud.yandex.ru/docs/compute/concepts/performance-levels
    }

    # Загрузочный диск в виртуальных машинах в Instance Groups
    boot_disk {
      initialize_params {
        image_id = "fd8iqpj5nifue99bshhi" 
        size     = 10
        type     = "network-hdd"
      }
    }

    network_interface {
      network_id = yandex_vpc_network.network.id
      subnet_ids = [
        yandex_vpc_subnet.subnet1.id,
        yandex_vpc_subnet.subnet2.id,
        yandex_vpc_subnet.subnet3.id,
      ]
      nat = false
    }
    scheduling_policy {
      preemptible = true
    }
    network_settings {
      type = "STANDARD"
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    zones = [
      "ru-central1-a",
      "ru-central1-b",
      "ru-central1-c",
    ]
  }

  deploy_policy {
    max_unavailable = 3
    max_creating    = 3
    max_expansion   = 3
    max_deleting    = 3
  }
}

resource "yandex_compute_instance_group" "workers" {
  name               = "kubernetes-workers"
  folder_id = yandex_resourcemanager_folder.folder.id
  service_account_id = yandex_iam_service_account.sa.id
  depends_on = [
    yandex_iam_service_account.sa,
    yandex_resourcemanager_folder_iam_member.sa-editor,
    yandex_vpc_network.network,
    yandex_vpc_subnet.subnet1,
    yandex_vpc_subnet.subnet2,
    yandex_vpc_subnet.subnet3,
  ]
  
  # Шаблон экземпляра, к которому принадлежит группа экземпляров.
  instance_template {

    # Имя виртуальных машин, создаваемых Instance Groups
    name = "worker-{instance.index}"
    # Ресурсы, которые будут выделены для создания виртуальных машин в Instance Groups
    resources {
      cores  = 2
      memory = 2
      core_fraction = 100 # Базовый уровень производительности vCPU. https://cloud.yandex.ru/docs/compute/concepts/performance-levels
    }

    # Загрузочный диск в виртуальных машинах в Instance Groups
    boot_disk {
      initialize_params {
        image_id = "fd8iqpj5nifue99bshhi" 
        size     = 10
        type     = "network-hdd"
      }
    }

    network_interface {
      network_id = yandex_vpc_network.network.id
      subnet_ids = [
        yandex_vpc_subnet.subnet1.id,
        yandex_vpc_subnet.subnet2.id,
        yandex_vpc_subnet.subnet3.id,
      ]
      nat = false
    }
    scheduling_policy {
      preemptible = true
    }
    network_settings {
      type = "STANDARD"
    }
  }

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  allocation_policy {
    zones = [
      "ru-central1-a",
      "ru-central1-b",
      "ru-central1-c",
    ]
  }

  deploy_policy {
    max_unavailable = 2
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }
}

resource "yandex_compute_instance_group" "ingresses" {
  name               = "kubernetes-ingresses"
  folder_id = yandex_resourcemanager_folder.folder.id
  service_account_id = yandex_iam_service_account.sa.id
  depends_on = [
    yandex_iam_service_account.sa,
    yandex_resourcemanager_folder_iam_member.sa-editor,
    yandex_vpc_network.network,
    yandex_vpc_subnet.subnet1,
    yandex_vpc_subnet.subnet2,
    yandex_vpc_subnet.subnet3,
  ]
  
  # Шаблон экземпляра, к которому принадлежит группа экземпляров.
  instance_template {

    # Имя виртуальных машин, создаваемых Instance Groups
    name = "ingress-{instance.index}"
    # Ресурсы, которые будут выделены для создания виртуальных машин в Instance Groups
    resources {
      cores  = 2
      memory = 2
      core_fraction = 100 # Базовый уровень производительности vCPU. https://cloud.yandex.ru/docs/compute/concepts/performance-levels
    }

    # Загрузочный диск в виртуальных машинах в Instance Groups
    boot_disk {
      initialize_params {
        image_id = "fd8iqpj5nifue99bshhi" 
        size     = 10
        type     = "network-hdd"
      }
    }

    network_interface {
      network_id = yandex_vpc_network.network.id
      subnet_ids = [
        yandex_vpc_subnet.subnet1.id,
        yandex_vpc_subnet.subnet2.id,
        yandex_vpc_subnet.subnet3.id,
      ]
      nat = true
    }
    metadata = {
      user-data = data.template_file.userdata.rendered
    }
    scheduling_policy {
      preemptible = true
    }
    network_settings {
      type = "STANDARD"
    }
  }

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  allocation_policy {
    zones = [
      "ru-central1-a",
      "ru-central1-b",
      "ru-central1-c",
    ]
  }

  deploy_policy {
    max_unavailable = 2
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }
}


