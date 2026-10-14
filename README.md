![CI](https://github.com/MPeets/airgapped-observability-lab/actions/workflows/ci.yml/badge.svg)

# airgapped-observability-lab

A self-hosted Prometheus, Alertmanager and Grafana stack built to run in a network with no
internet access. Everything is pinned, configured as code, tested, and installed from a verified
offline bundle. It monitors Linux and Windows hosts, probes devices that can't run an exporter
(the usual situation with OT equipment), and watches TLS certificates issued by an internal CA.

## What this demonstrates

- **Offline delivery:** one bundle with the repo, every container image and SHA256 checksums.
  The installer verifies files and image IDs, then starts the stack with registry pulls disabled
- **Monitoring as code:** datasources, dashboards, alert rules, routing and targets all live in
  git and are read-only in the UI
- **Tested alerting:** promtool unit tests for every alert (including cases that must *not* fire),
  routing tests, and an end-to-end smoke test that follows an alert all the way to the receiver
- **OT-relevant probing:** ICMP and TCP checks for devices without exporters, and certificate
  expiry monitoring against an internal CA
- **Hardened by default:** read-only containers, no Linux capabilities beyond `NET_RAW` for ping,
  non-root processes, localhost-only ports, resource limits, bounded logs and storage, and no
  outbound calls from Grafana

## Quick start

    cp .env.example .env              # then set GRAFANA_ADMIN_PASSWORD
    ./scripts/gen-lab-certs.sh        # lab CA + demo certificate (certs/ is gitignored)
    ./scripts/check.sh                # validate everything before starting
    docker compose up -d
    ./scripts/smoke-test.sh           # confirm the whole stack works end to end

- Grafana: http://localhost:3000 (dashboards under **Lab**)
- Prometheus: http://localhost:9090
- Alertmanager: http://localhost:9093
- Alert notifications: `docker compose logs -f webhook-logger`

## Components

| Component | Purpose | Exposed |
|---|---|---|
| Prometheus | Scrapes metrics, evaluates rules, stores time series | 127.0.0.1:9090 |
| Alertmanager | Routing, grouping and inhibition of alerts | 127.0.0.1:9093 |
| Grafana | Dashboards, provisioned as code | 127.0.0.1:3000 |
| node_exporter | Linux host metrics | internal only |
| blackbox_exporter | Probes from outside: HTTP, ICMP, TCP, TLS | internal only |
| webhook-logger | Lab stand-in for a real notification receiver | internal only |
| tls-demo | HTTPS endpoint signed by the lab CA | internal only |
| windows_exporter | Windows host metrics, installed on the Windows host itself (optional) | port 9182 on that host |

## Alerts

| Alert | Severity | Routed to |
|---|---|---|
| TargetDown | critical | oncall |
| HostDiskAlmostFull | critical | oncall |
| ProbeFailed | critical | oncall |
| TLSCertExpiryCritical | critical | oncall |
| HostHighCpu, HostHighMemory | warning | team |
| HostDiskWillFillIn24h | warning | team |
| ProbeSlow | warning | team |
| TLSCertExpiringSoon | warning | team |
| Watchdog | none | watchdog (always firing, proves alerting works) |

Every alert links to its section in [docs/runbook.md](docs/runbook.md). Host alerts cover Linux
and Windows through shared recording rules.

## Adding targets

Targets live in `prometheus/targets/<job>/*.yml`. Add or edit a file and Prometheus picks it up
within 30 seconds, with no restart or reload.

    - targets: ["10.0.5.20:9100"]
      labels:
        site: substation-north
        role: scada-server

## Testing

| Check | Command | Runs in CI |
|---|---|---|
| Config, rule unit tests, routing tests, blackbox config, runbook links | `./scripts/check.sh` | every push and PR |
| Shell scripts, Python helpers, dashboard JSON | shellcheck, py_compile, json.tool | every push and PR |
| Full stack end to end | `./scripts/smoke-test.sh` | every push and PR |
| Offline bundle installed with registries blocked, then smoke tested | `./scripts/bundle.sh` + `install.sh` | main and manual runs |

## Offline install

On a machine with internet access (optionally put the windows_exporter MSI in `vendor/` first):

    ./scripts/bundle.sh

Carry `dist/observability-lab-<commit>.tar` and its `.sha256` file across, then on the offline host:

    sha256sum -c observability-lab-<commit>.tar.sha256
    tar -xf observability-lab-<commit>.tar
    cd observability-lab-<commit>
    ./install.sh

The installer verifies every file and image before starting anything, and never pulls from a registry.

## Documentation

- [Architecture](docs/architecture.md): how it fits together, design decisions, and what changes
  between this lab and production
- [Runbook](docs/runbook.md): what to do for each alert
- [OT adaptation](docs/ot-adaptation.md): running this in an industrial network (Purdue model,
  safe probing of field devices, maintenance windows)

## Repository layout

    alertmanager/        routing, grouping and inhibition
    blackbox/            probe modules (HTTP, ICMP, TCP, TLS against the internal CA)
    docs/                architecture, runbook, OT notes
    grafana/             provisioning and dashboards
    prometheus/          config, rules, rule unit tests, file-based targets
    scripts/             check, smoke test, certificates, offline bundle and installer
    tools/               lab helpers (webhook receiver, TLS demo service)
    .github/workflows/   CI