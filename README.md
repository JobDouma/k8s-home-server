# k8s-home-server

3-node Talos Linux Kubernetes homelab managed with Flux GitOps.

## Stack

| Layer | Tool |
|---|---|
| OS | Talos Linux |
| GitOps | Flux v2 |
| Ingress | Traefik |
| Certificates | cert-manager (internal CA) |
| Storage | local-path-storage (default), TrueNAS NFS provisioner |
| Auth | Authentik (SSO) |
| DNS | Blocky (ad-blocking, custom LAN records) |
| Networking | Cilium (CNI), MetalLB (L2), Tailscale (VPN) |
| Monitoring | VictoriaMetrics, Grafana, Loki, Promtail |
| Security | Falco, Kyverno (policies) |
| Notifications | Gotify |
| Dependency updates | Renovate |
| Management | Omni (Talos cluster management) |

## Structure

```text
clusters/                       # Flux bootstrap and cluster config
talos-home/                     # Cluster-specific Kustomizations
infrastructure/                 # Core platform components
├── cert-manager/
├── traefik/
├── authentik/
├── metallb/
├── cilium/
├── metrics-server/
├── local-path-storage/
├── storage/                    # Static PV/PVCs for media (TrueNAS NFS)
└── omni/                       # Omni + Garage (Docker Compose, host-level)

apps/                           # Applications grouped by namespace
└── talos-home/                 # App resources (HelmReleases, configs, etc.)
```

## Apps

| Category | Apps |
|---|---|
| Media | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Recyclarr, Jellyseerr, Flaresolverr |
| Photos | Immich |
| Monitoring | VictoriaMetrics, Grafana, Loki, Promtail, Falco, Uptime Kuma |
| Tools | Joplin, FreshRSS, Dashy, n8n, Gotify, Argus (port scanner) |
| Infrastructure | Blocky, CoreDNS, Kyverno, Tailscale, Renovate, Reloader |

All web services are exposed through Traefik on `*.lan` with TLS certificates signed by the internal homelab CA. Blocky provides DNS resolution for these domains and acts as an ad-blocking resolver for the entire LAN.

## Secrets

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) using age before being committed.

Secrets are stored as `*.secret.yaml` or `*.sops.yaml` files and decrypted by Flux during reconciliation.

```bash
# Encrypt a secret
sops --encrypt --age <recipient> --encrypted-regex '^(data|stringData)$' secret.yaml
```

The age public key is stored in `cosign.pub`; the corresponding private key is not stored in the repository.

## Networking

Cilium provides the CNI with kube-proxy replacement, L2 announcements, and Hubble observability.

MetalLB allocates LoadBalancer IPs from the `192.168.2.x` range for services that need direct LAN access:

- `192.168.2.53` – Blocky (DNS)
- `192.168.2.100` – Traefik (ingress)
- `192.168.2.50` – Jellyfin (direct UDP for DLNA)
- `192.168.2.101–110` – General pool for other LoadBalancer services

Tailscale provides secure remote access via the Tailscale operator, including Ingress, subnet routing, and ProxyGroup functionality. Services such as Grafana can be exposed directly to the tailnet with MagicDNS names and automatic Let's Encrypt certificates.

## Flux

```bash
# Check status of all resources
flux get all -A

# Force reconcile a Kustomization
flux reconcile kustomization flux-system --with-source

# Reconcile a specific app HelmRelease
flux reconcile helmrelease <name> -n <namespace>
```

## Updating Omni

Omni runs as a Docker Compose service on the host `ubuntu-server`, outside the Kubernetes cluster. Its configuration is stored in `infrastructure/omni/` and updated using the `upgrade.sh` script.

```bash
cd infrastructure/omni
./upgrade.sh   # decrypts secrets, updates compose files, restarts containers
```

## Adding a New Application

1. Create a namespace if needed and a HelmRelease using the `bjw-s/app-template` chart.
2. Add the required Certificate and IngressRoute resources to expose the service through Traefik.
3. Add the new files to `apps/talos-home/kustomization.yaml` under the appropriate category.
4. Commit and push — Flux will apply the changes automatically.

## Network Policies

The cluster enforces network segmentation using Kubernetes NetworkPolicies. Most namespaces use a default-deny policy, with explicit ingress and egress rules defined for each workload.

For example, media applications can communicate with each other and with the internet, but cannot communicate with workloads in other namespaces unless explicitly allowed.

Notable exceptions are `kube-system`, `metallb-system`, and `tailscale`, which have allow-all policies due to their privileged nature.
