# k8s-home-server

Personal Kubernetes homelab running on [Talos Linux](https://www.talos.dev/), managed with [Flux](https://fluxcd.io/) GitOps.

## Stack

| Layer | Tool |
|---|---|
| OS | Talos Linux |
| GitOps | Flux v2 |
| Ingress | Traefik |
| Certificates | cert-manager |
| Storage | Longhorn |
| Auth | Authentik |
| Secrets | SOPS + age |
| Notifications | Gotify |
| Dependency updates | Renovate |

## Structure

```
clusters/        # Flux bootstrap and cluster config
infrastructure/  # Core platform (cert-manager, traefik, longhorn, authentik, ...)
apps/            # Applications (jellyfin, sonarr, radarr, gotify, ...)
```

## Apps

- **Media:** Jellyfin, Sonarr, Radarr, Prowlarr, SABnzbd, qBittorrent, Recyclarr, Jellyseerr
- **Monitoring:** Prometheus, Grafana, Loki, Promtail, Tempo, Falco
- **Tools:** Joplin, FreshRSS, Dashy, Headlamp, Blocky, Gotify, Renovate, Velero

## Secrets

All secrets are encrypted with [SOPS](https://github.com/getsops/sops) using age before being committed. Never commit plaintext secrets.

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