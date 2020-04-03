data "terraform_remote_state" "nomad" {
  backend = "remote"

  config = {
    organization = "webpage-counter"
    workspaces = {
      name = "ops-aws-nomad"
    }
    token = var.token
  }
}

provider "nomad" {
  address = "http://${data.terraform_remote_state.nomad.outputs.UI}"
}

resource "nomad_job" "fabio" {
  jobspec = <<EOT
job "fabio" {
  datacenters = ["dc1"]
  type = "system"

  group "fabio" {
    task "fabio" {
      driver = "docker"
      config {
        image = "fabiolb/fabio"
        network_mode = "host"
      }

      resources {
        cpu    = 200
        memory = 128
        network {
          mbits = 20
          port "lb" {
            static = 9999
          }
          port "ui" {
            static = 9998
          }
        }
      }
    }
  }
}
EOT
}
resource "nomad_job" "db" {
  jobspec = <<EOT
job "db" {
  datacenters = ["dc1"]

  group "db" {
    network {
      mode = "bridge"
    }
    service {
      name = "redis"
      port = "6379"

      connect {
        sidecar_service {}
      }
    }
    task "db" {           # The task stanza specifices a task (unit of work) within a group
      driver = "docker"      # This task uses Docker, other examples: exec, LXC, QEMU
      config {
        image = "redis:4-alpine" # Docker image to download (uses public hub by default)
        args = [
          "redis-server", "--requirepass", "${var.dbpass}"
         
        ]  
      }
    } 
  }
}
EOT
}


resource "nomad_job" "app" {
  jobspec = <<EOT
job "app" {
  datacenters = ["dc1"]

  group "counter" {
    count = 3
    update {
      max_parallel     = 1
      canary           = 3
      min_healthy_time = "10s"
      healthy_deadline = "5m"
      progress_deadline = "10m"
      auto_revert      = true
      auto_promote     = false
    }
    network {
      mode = "bridge"

      port "http" {
  
        to     = 5000
      }
    }

    service {
      name = "webapp-proxy"
      port = "http"
      connect {
        sidecar_service {
            proxy {
                upstreams {
                  destination_name = "redis"
                  local_bind_port = 6479
                }
            }
        }
      }
    }

    service {
      name = "webapp"
      port = "http"
      tags = ["urlprefix-/"]
      check {
        name     = "HTTP Health Check"
        type     = "http"
        port     = "http"
        path     = "/health"
        interval = "5s"
        timeout  = "2s"
      }
    }
    
    task "app" {
      driver = "docker"      
      config {
        image = "denov/webpage-counter:0.1.4" 
      }
    }
  }
}
EOT
}
