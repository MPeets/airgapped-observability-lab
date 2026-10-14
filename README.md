![CI](https://github.com/MPeets/airgapped-observability-lab/actions/workflows/ci.yml/badge.svg)

# airgapped-observability-lab

A self-hosted Prometheus and Grafana monitoring stack built to run without internet access.
Everything is pinned, configured as code, and installable from an offline bundle.

## Quick start

    cp .env.example .env
    
    Set GRAFANA_ADMIN_PASSWORD in .env before starting.

    ./scripts/gen-lab-certs.sh      # lab CA + demo certificate (certs/ is gitignored)
    
    docker compose up -d

Prometheus: http://localhost:9090 (Status > Targets should show the prometheus job as UP)

## Components

| Component     | Purpose                              | Exposed            |
| ------------- | ------------------------------------ | ------------------ |
| Prometheus    | Scrapes and stores metrics           | 127.0.0.1:9090     |
| node_exporter | Linux host metrics (CPU, memory, disk) | Internal network only |
| Grafana       | Dashboards, provisioned as code      | 127.0.0.1:3000     |
| Alertmanager   | Routing, grouping, inhibition of alerts | 127.0.0.1:9093 |
| webhook-logger | Lab stand-in for a real notification receiver | Internal network only |
| blackbox_exporter | Probes from outside: HTTP, ICMP, TCP | Internal network only |
| tls-demo | HTTPS endpoint signed by the lab CA, for certificate monitoring | Internal network only |


## Adding targets

Targets live in prometheus/targets/<job>/*.yml. Add or edit a file and
Prometheus picks it up automatically, no restart or reload.

    - targets: ["10.0.5.20:9100"]
      labels:
        site: substation-north
        role: scada-server

## Offline install

On a machine with internet access (optionally put the windows_exporter MSI in vendor/ first):

    ./scripts/bundle.sh

Carry dist/observability-lab-<commit>.tar and its .sha256 file across, then on the offline host:

    sha256sum -c observability-lab-<commit>.tar.sha256
    tar -xf observability-lab-<commit>.tar
    cd observability-lab-<commit>
    ./install.sh

The installer verifies every file and image before starting anything, and never pulls from a registry.

## Testing

After `docker compose up -d`, check the whole stack end to end:

    ./scripts/smoke-test.sh

CI runs config validation, the rule tests and this smoke test on every push, and on
main it also builds the offline bundle and installs it with container registries blocked.

## Status

Work in progress.