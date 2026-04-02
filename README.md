# k8s-home-server
Personal Kubernetes homelab running on [Talos Linux](https://www.talos.dev/), managed with [Flux](https://fluxcd.io/) GitOps.

## Stack
| Layer | Tool |
|---|---|
| OS | Talos Linux |
| GitOps | Flux v2 |
| Ingress | Traefik |
| Certificates | cert-manager |
| Storage | Longhorn + TrueNAS NFS |
| Auth | Authentik (SSO) |
| DNS | Blocky |
| Secrets | SOPS + age |
| Networking | MetalLB, Tailscale |
| Notifications | Gotify |
| Dependency updates | Renovate |

## Structure
```
clusters/        # Flux bootstrap and cluster config
infrastructure/  # Core platform (cert-manager, traefik, longhorn, authentik, metallb, ...)
apps/            # Applications (jellyfin, sonarr, radarr, immich, ...)
```

## Apps
| Category | Apps |
|---|---|
| Media | Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Recyclarr, Jellyseerr |
| Photos | Immich |
| Monitoring | VictoriaMetrics, Grafana, Loki, Promtail, Falco, Uptime Kuma |
| Tools | Joplin, FreshRSS, Dashy, Headlamp, Renovate, Velero |

## Secrets
All secrets are encrypted with [SOPS](https://github.com/getsops/sops) using age before being committed.

```bash
# Encrypt a secret
sops --encrypt --age <recipient> --encrypted-regex '^(data|stringData)$' secret.yaml
```

## Flux
```bash
# Check status
flux get all -A

# Force reconcile
flux reconcile kustomization flux-system --with-source
```