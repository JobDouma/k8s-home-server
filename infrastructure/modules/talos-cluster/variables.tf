variable "cluster_name" {
  description = "Name of the Talos/Kubernetes cluster (not a node name)."
  type        = string
}

variable "control_plane_nodes" {
  description = "Control-plane nodes keyed by node name. 'generation' must change whenever the node's VM is rebuilt."
  type = map(object({
    ip         = string
    generation = string
  }))
}

variable "bootstrap_node" {
  description = "Key in control_plane_nodes of the node that runs etcd bootstrap."
  type        = string
}

variable "cluster_vip" {
  description = "Floating VIP for the Kubernetes API (outside the DHCP range). Null = use the bootstrap node's IP."
  type        = string
  default     = null
}

variable "talos_version" {
  description = "Talos version used as the machine-config contract (e.g. v1.14.6)."
  type        = string
}