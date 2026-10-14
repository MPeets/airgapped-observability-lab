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

## Status

Work in progress.