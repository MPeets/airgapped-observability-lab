# airgapped-observability-lab

A self-hosted Prometheus and Grafana monitoring stack built to run without internet access.
Everything is pinned, configured as code, and installable from an offline bundle.

## Quick start

    cp .env.example .env
    docker compose up -d

Prometheus: http://localhost:9090 (Status > Targets should show the prometheus job as UP)

## Status

Work in progress.