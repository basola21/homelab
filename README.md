# Homelab Media Stack

Multi-stack Docker Compose setup for a self-hosted media server.

## Stack layout

```
/opt/stacks/
  vpn/        → gluetun (all download traffic routes through here)
  downloads/  → qbittorrent, nzbget, deunhealth
  media/      → sonarr, radarr, lidarr, bazarr, prowlarr, flaresolverr, ytdl-sub
  requests/   → seerr
  infra/      → ntfy, uptime-kuma, watchtower, portainer, scraparr, cadvisor
  .env        → shared environment variables (never commit this)
```

## First-time setup

### 1. Clone and configure

```bash
git clone <repo> ~/docker/homelab
cd ~/docker/homelab
cp .env.example .env
nano .env   # fill in your values
```

Symlink `.env` into each stack directory so Docker Compose can resolve `${VAR}` substitutions when run from within a stack directory:

```bash
for stack in vpn downloads media requests infra; do
  ln -s ~/docker/homelab/.env ~/docker/homelab/$stack/.env
done
```

### 2. Create the shared Docker network

Run **once** on the host. All stacks reference this network as `external`.

```bash
docker network create \
  --driver bridge \
  --subnet 172.39.0.0/24 \
  servarrnetwork
```

Verify:

```bash
docker network inspect servarrnetwork
```

### 3. Create data directories

Run **once** on the host. The `/data` layout prevents file copies — everything stays on the same filesystem.

```bash
mkdir -p /data/downloads/{torrents,usenet}
mkdir -p /data/{movies,tv,music,youtube}
```

Set ownership to match `PUID`/`PGID` in your `.env`:

```bash
chown -R 1000:1000 /data
```

### 4. Start stacks in order

The VPN must be healthy before downloads can start.

```bash
# 1. Start VPN first
cd /opt/stacks/vpn && docker compose up -d

# 2. Wait for gluetun to be healthy, then start downloads
docker inspect --format='{{.State.Health.Status}}' gluetun
# (repeat until output is "healthy")
cd /opt/stacks/downloads && docker compose up -d

# 3. Start remaining stacks (order doesn't matter)
cd /opt/stacks/media     && docker compose up -d
cd /opt/stacks/requests  && docker compose up -d
cd /opt/stacks/infra     && docker compose up -d
```

---

## Day-to-day operations

### Pull updates for a stack

```bash
cd /opt/stacks/media
docker compose pull
docker compose up -d
```

### Restart a single container

```bash
docker restart sonarr
```

### View logs

```bash
docker logs -f sonarr
docker logs -f gluetun
```

### Stop everything

```bash
for stack in downloads media requests infra vpn; do
  cd /opt/stacks/$stack && docker compose down
done
```

---

## Networking

| Container      | IP            | Port  | Stack     |
|----------------|---------------|-------|-----------|
| gluetun        | 172.39.0.2    | —     | vpn       |
| sonarr         | DHCP          | 8989  | media     |
| radarr         | DHCP          | 7878  | media     |
| lidarr         | DHCP          | 8686  | media     |
| bazarr         | DHCP          | 6767  | media     |
| ytdl-sub       | DHCP          | —     | media     |
| seerr          | DHCP          | 5055  | requests  |
| flaresolverr   | DHCP          | —     | media     |
| prowlarr       | DHCP          | 9696  | media     |
| cadvisor       | DHCP          | 8090  | infra     |
| scraparr       | DHCP          | 7100  | infra     |
| ntfy           | DHCP          | 8085  | infra     |
| uptime-kuma    | DHCP          | 3001  | infra     |
| portainer      | DHCP          | 9000  | infra     |
| watchtower     | DHCP          | —     | infra     |

**qbittorrent** and **nzbget** share gluetun's network stack — reach them at `172.39.0.2:8080` and `172.39.0.2:6789`.

Use container names for inter-container communication (e.g. `http://prowlarr:9696`, `http://sonarr:8989`). Docker DNS resolves these automatically within `servarrnetwork`.

---

## Infra containers

### Portainer

Access at `http://<host-ip>:9000`. On first launch you must set an admin password within **5 minutes** or Portainer locks itself — it times out for security. If you miss it:

```bash
docker restart portainer
```

### Watchtower

Updates all containers automatically at 4am daily and removes old images. To exclude a container from auto-updates, add this label:

```yaml
labels:
  - com.centurylinklabs.watchtower.enable=false
```

To trigger an immediate update manually:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower --run-once
```

### Uptime Kuma

Access at `http://<host-ip>:3001`. After first login, add monitors for:

- `http://sonarr:8989` — Sonarr
- `http://radarr:7878` — Radarr
- `http://prowlarr:9696` — Prowlarr
- `http://seerr:5055` — Seerr
- `http://qbittorrent:8080` — qBittorrent (via gluetun IP `172.39.0.2:8080`)
- `http://ntfy:80/v1/health` — ntfy
- Proxmox and router via ICMP ping

Set notification channel to ntfy for push alerts.

### Scraparr

Prometheus exporter for the \*arr suite. Metrics endpoint: `http://<host-ip>:7100/metrics`

Config lives at `./infra/scraparr/config.yaml`. You must fill in API keys **after** the \*arr apps are running:

1. Sonarr → Settings → General → API Key
2. Radarr → Settings → General → API Key
3. Lidarr → Settings → General → API Key
4. Bazarr → Settings → General → Security → API Key
5. Prowlarr → Settings → General → API Key

Then restart scraparr to pick up the config:

```bash
docker restart scraparr
```

Scraparr works on the `servarrnetwork` so it can reach all \*arr containers by name directly.

---

### ntfy

Config lives at `./infra/ntfy/config/server.yml`. Minimal example:

```yaml
base-url: http://<host-ip>:8085
cache-file: /var/cache/ntfy/cache.db
auth-file: /var/cache/ntfy/auth.db
auth-default-access: deny-all
```

---

## VPN health check

Verify qbittorrent is actually going through the VPN:

```bash
docker exec -it qbittorrent curl -s https://ipinfo.io
```

The IP should match your VPN exit node, not your home IP.

---

## Troubleshooting

### gluetun not healthy

```bash
docker logs gluetun
```

Common causes: wrong WireGuard keys, port not forwarded, `FIREWALL_VPN_INPUT_PORTS` mismatch.

### downloads stuck after VPN reconnect

deunhealth watches qbittorrent's healthcheck and restarts it automatically. Check:

```bash
docker logs deunhealth
```

### Reset qbittorrent config

```bash
docker stop qbittorrent
rm -rf /opt/stacks/downloads/qbittorrent
docker start qbittorrent
```

---

## Notes on cross-stack VPN routing

`network_mode: container:gluetun` (used in downloads) differs from `network_mode: service:gluetun`:

- `service:gluetun` — only works within the **same** compose project
- `container:gluetun` — works across compose projects, references by container name

The VPN stack must be running before the downloads stack starts.
