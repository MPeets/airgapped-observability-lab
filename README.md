# airgapped-observability-lab

A self-hosted Prometheus and Grafana monitoring stack built to run without internet access.
Everything is pinned, configured as code, and installable from an offline bundle.

## Quick start

    cp .env.example .env
    docker compose up -d

Prometheus: http://localhost:9090 (Status > Targets should show the prometheus job as UP)

## Components

| Component     | Purpose                              | Exposed            |
| ------------- | ------------------------------------ | ------------------ |
| Prometheus    | Scrapes and stores metrics           | 127.0.0.1:9090     |
| node_exporter | Linux host metrics (CPU, memory, disk) | Internal network only |

## Status

Work in progress.