terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.99.0"
    }
  }

  backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "retail-bucket-ru-central1-a"
    region     = "ru-central1"
    key        = "terraform.tfstate"

    skip_region_validation      = true
    skip_credentials_validation = true
  }
}