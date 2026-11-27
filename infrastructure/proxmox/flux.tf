provider "flux" {
  kubernetes = {
    config_path = "${path.module}/kubeconfig"
  }

  git = {
    url    = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    branch = var.github_branch
    http = {
      username = "git"
      password = var.github_token
    }
  }
}

resource "flux_bootstrap_git" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    kubernetes_secret.sops_age,
    local_file.kubeconfig,
  ]

  path                 = var.flux_path
  version              = var.flux_version
  network_policy       = true
  watch_all_namespaces = true

  # Keep the bootstrap manifests in Git so they are version-controlled
  # alongside clusters/talos-home/flux-system/.
  delete_git_manifests = false

  components_extra = [
    "image-reflector-controller",
    "image-automation-controller",
  ]
}

resource "kubernetes_secret" "sops_age" {
  depends_on = [talos_machine_bootstrap.this]

  metadata {
    name      = "sops-age"
    namespace = "flux-system"
  }

  data = {
    "age.agekey" = file("${path.module}/age.agekey")
  }
}