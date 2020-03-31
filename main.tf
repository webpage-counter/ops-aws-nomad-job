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
