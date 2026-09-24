# Monitoring

Alerting for the cluster: crashing pods, certificates that expire or fail to
renew, ArgoCD apps out of sync or degraded, disk/memory pressure, HTTPS
endpoints down. Notifications are pushed to **ntfy**.

Plain Prometheus (no Operator, no Helm) + Alertmanager, no Grafana: the
Prometheus UI is enough for queries and debugging.

## How it works

Three layers, each one catching failures the others cannot see:

```
1. inside the cluster
   kube-state-metrics ─┐
   node-exporter ──────┤
   kubelet (API proxy) ┼─→ Prometheus ──rules──→ Alertmanager ──→ ntfy
   cert-manager :9402 ─┤                              │
   argocd :8082/8083 ──┘                              │
                                                      │
2. "client-side" probes                               │
   blackbox-exporter → https://<app>.${DOMAIN}        │
   (HTTP 2xx + TLS cert actually served by Traefik)   │
                                                      │
3. outside the cluster                                │
   Watchdog alert (always firing) ────every 1m────────┴──→ healthchecks.io
   no ping for a few minutes → healthchecks.io notifies (node down, network
   down, monitoring down)
```

On top of that, **ArgoCD Notifications** (configured in
[08.argocd](../08.argocd/README.md#notifications)) sends a message with the
app name and the sync error as soon as a sync fails.

## Components

- **Prometheus** — scrapes metrics from all targets, stores them (TSDB) and evaluates the alerting rules.
  It decides *what* is wrong, but does not send notifications itself.
- **Alertmanager** — separate project of the Prometheus team: receives alerts from Prometheus.
  Groups, deduplicates and silences them, then routes them to ntfy / healthchecks.io.
- **kube-state-metrics** — Kubernetes community project: reads object state from the API server.
  Exposes it as metrics (pods in CrashLoopBackOff, restarts, deployment replicas).
- **node-exporter** — Prometheus team project, one pod per node (DaemonSet).
  Exposes the node's hardware and OS metrics: disk, memory, CPU, network.
- **blackbox-exporter** — Prometheus team project that probes services "from outside", like a client.
  Tells whether an URL answers, with which HTTP code, and when its TLS certificate expires.
- **healthchecks.io** — external SaaS acting as dead man's switch.
  Expects a ping every minute: if the pings stop, it notifies you.
- **ntfy** — push notification service: publishing is an HTTP POST to a topic URL.
  The ntfy app on the phone subscribes to the topic and receives the alerts.

## What is deployed

- Namespace `monitoring` (PodSecurity `privileged` — node-exporter needs
  hostNetwork/hostPID/hostPath, Prometheus keeps its TSDB on a hostPath)
- `02_rbac.yaml` — ServiceAccount + read-only ClusterRole for Prometheus
- `03_prometheus-config.yaml` — `prometheus.yml` (scrape jobs) and `rules.yml`
  (alerting rules)
- `04_prometheus.yaml` — Prometheus, 15 days retention, TSDB on
  `/var/mnt/hdd-data-1/prometheus-data` (shared local Talos disk)
- `05_alertmanager.yaml` — Alertmanager + its config in a Secret (ntfy and
  healthchecks.io URLs from `.env`)
- `06_kube-state-metrics.yaml` — upstream manifest, pinned to v2.20.0
- `07_node-exporter.yaml` — DaemonSet
- `08_blackbox-exporter.yaml` — HTTPS probes
- `09_ingress.yaml` — `prometheus.${DOMAIN}` and `alertmanager.${DOMAIN}` via
  Traefik, TLS via cert-manager. **No authentication**: reachable only from LAN
  and Tailscale (split DNS), never publish these hosts on public DNS.

## Alerts

| Alert | Fires when | for |
|---|---|---|
| Watchdog | always (dead man's switch → healthchecks.io) | – |
| TargetDown | a scrape target is down | 5m |
| PodCrashLooping | container in `CrashLoopBackOff` | 10m |
| PodRestartingOften | more than 3 restarts in the last hour | – |
| ImagePullFailing | `ErrImagePull` / `ImagePullBackOff` | 15m |
| PodNotReady | pod not Ready (completed pods excluded) | 15m |
| DeploymentReplicasMismatch | available replicas ≠ desired | 15m |
| CertExpiringSoon | cert-manager certificate expires in < 14 days | 1h |
| CertNotReady | cert-manager certificate not Ready (renewal failing) | 30m |
| ProbeFailed | HTTPS endpoint not answering 2xx | 5m |
| ProbeCertExpiring | certificate served by Traefik expires in < 14 days | 1h |
| ArgoAppOutOfSync | ArgoCD app not `Synced` | 30m |
| ArgoAppUnhealthy | ArgoCD app not `Healthy`/`Progressing` | 15m |
| NodeDiskAlmostFull | `/var` or `/var/mnt/*` below 10% free | 15m |
| NodeMemoryHigh | less than 10% memory available | 15m |
| PVCAlmostFull | PVC below 10% free (only volumes reporting stats) | 15m |

Let's Encrypt certificates last 90 days and cert-manager renews them 30 days
before expiry: a certificate under 14 days means renewal has been failing for
two weeks.

## Prerequisites

1. **ntfy topic** — pick a long random topic name (on ntfy.sh the topic is the
   only secret) and subscribe to it from the ntfy app on your phone.

2. **healthchecks.io check** — create a check with **period 1 minute** and
   **grace 5 minutes**, and configure its integrations (email, or ntfy too) to
   notify you when it goes down. Copy its ping URL.

3. **Local disk** — the TSDB goes into `/var/mnt/hdd-data-1/prometheus-data`,
   created on first start (see [04.storage](../04.storage/README.md), "Local Disk").

## Required env

```bash
DOMAIN=example.com                             # already set
NTFY_URL=https://ntfy.sh/<long-random-topic>
HEALTHCHECKS_PING_URL=https://hc-ping.com/<uuid>
```

## Apply

The manifests contain literal `$1`, `$labels`, `$value` (relabeling and alert
templates): envsubst must receive an **explicit list of variables**, otherwise
it replaces them with empty strings.

```bash
# set -a exports everything sourced — required, envsubst only sees exported vars
set -a; source ../.env; set +a
kubectl kustomize ./monitoring | envsubst '${DOMAIN} ${NTFY_URL} ${HEALTHCHECKS_PING_URL}' | kubectl apply -f -
```

Prometheus does not watch its ConfigMap: after changing scrape jobs or rules,
re-apply and restart it:

```bash
kubectl -n monitoring rollout restart deploy prometheus
```

Same for Alertmanager after a change to its Secret:

```bash
kubectl -n monitoring rollout restart deploy alertmanager
```

## Verify

1. All pods running:
   ```bash
   kubectl -n monitoring get pods
   ```
2. Open `https://prometheus.${DOMAIN}/targets`: every target must be **UP**
   (prometheus, alertmanager, kube-state-metrics, node-exporter, cert-manager,
   argocd, kubelet, blackbox-https).
3. Open `https://alertmanager.${DOMAIN}`: the `Watchdog` alert is listed, and
   the healthchecks.io check turns green within a minute or two.
4. **Crash test** — a pod that always fails:
   ```bash
   kubectl run crashtest --image=busybox --restart=Always -- sh -c "exit 1"
   ```
   After ~10-15 minutes `PodCrashLooping` arrives on ntfy. Then clean up; the
   "resolved" notification follows:
   ```bash
   kubectl delete pod crashtest
   ```
5. **Dead man's switch** — stop Alertmanager; after the grace period
   healthchecks.io notifies you. Then bring it back:
   ```bash
   kubectl -n monitoring scale deploy alertmanager --replicas=0
   kubectl -n monitoring scale deploy alertmanager --replicas=1
   ```

## Notes

- **Adding a probe:** append the URL to the `blackbox-https` job targets in
  `03_prometheus-config.yaml`, re-apply and restart Prometheus.
- **Silencing:** during planned maintenance create a silence from the
  Alertmanager UI instead of ignoring notifications.
- **Talos control plane:** scheduler, controller-manager and etcd listen on
  localhost on Talos, so they are not scraped. A broken control plane still
  shows up as failing workloads, probes, or a silent Watchdog.
- **Certificates outside Kubernetes:** the `talosconfig` client certificate
  (1 year validity) is not monitored. Check it with
  `talosctl config info` and regenerate it before it expires.
- **Why `runAsUser: 0` for Prometheus:** the kubelet creates the hostPath
  directory as `root:root 0755` and the image runs as `nobody`; running as root
  avoids a chown initContainer (same trade-off as pihole).
