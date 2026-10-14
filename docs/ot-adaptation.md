# Adapting this to an OT environment

This lab runs on one machine. Monitoring industrial systems (substations, plants, pumping
stations) changes several things. These notes cover what I'd adapt and why.

## Where the monitoring stack lives

OT networks are usually segmented following the Purdue model: field devices (level 0), controllers
such as PLCs (level 1), SCADA and operator stations (level 2), site operations (level 3), with a
DMZ (level 3.5) separating them from enterprise IT (levels 4 and 5).

- **Prometheus for OT runs inside the OT network**, at level 3, or one per site. It must not
  depend on anything in enterprise IT to keep working.
- **Scraping crosses as few boundaries as possible.** Each firewall rule from Prometheus to a
  device subnet is an explicit, reviewed exception, scoped to the exporter or probe port only.
- **Central views go through the DMZ.** If enterprise IT needs dashboards, a central Prometheus
  or Grafana in the DMZ pulls from the site Prometheus (federation), rather than IT reaching down
  into OT.

## What to monitor on OT devices

Most PLCs, RTUs and meters can't run an exporter. In order of how much they tell you:

1. **Reachability:** ICMP probe (`blackbox-icmp`). Cheap, and catches power and network faults.
2. **Service port:** TCP connect on the industrial protocol port (`tcp_connect` module), for
   example Modbus/TCP 502, OPC UA 4840, IEC 60870-5-104 on 2404. A device can answer ping while
   its protocol stack has hung.
3. **Protocol-level data:** dedicated exporters exist for some protocols (Modbus, SNMP for network
   gear). Only with care, see below.
4. **Data freshness:** the most dangerous failure in SCADA is stale data that looks valid. Where
   possible, alert when a value hasn't updated within its expected interval.

## Rules that change in OT

- **Read-only, always.** Monitoring must never write to a device. Protocol exporters get
  read-only access where the device supports it.
- **Gentle polling.** Old controllers can be overwhelmed by frequent polling. Start with longer
  scrape and probe intervals (60s or more) for field devices, and agree them with the device owner.
- **No discovery scanning.** Network scans can crash fragile OT devices. Targets are listed
  explicitly in `prometheus/targets/`, never discovered by sweeping a subnet.
- **Alerts lead to people, not actions.** An alert on an industrial system goes to whoever is
  responsible for it. Monitoring should not automatically restart or power-cycle anything.
- **Certificates need longer lead times.** Many devices can't renew automatically, and changing
  a certificate may require a maintenance window. Hence the 30-day warning in this lab.
- **Maintenance windows.** Planned outages should be silenced in Alertmanager in advance, so the
  people on call trust that an alert means something.

## Moving software in

Everything follows the offline bundle process in this repo: pinned versions, checksums verified
on the OT side before installation, no pulls from the internet, and a record of exactly what was
installed (commit, image IDs). In a real environment the bundle would also be signed and scanned
before crossing.