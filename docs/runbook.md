# Runbook

One section per alert. Every alert's `runbook` annotation links to its section here,
and `scripts/check.sh` fails if a link points to a section that doesn't exist.

Each entry answers the same questions: what it means, what to check first, likely
causes, how to fix it, and when to escalate.

Commands assume you're in the repository folder on the monitoring host.

---

## TargetDown

**Severity:** critical. **Fires when:** Prometheus has failed to scrape an exporter for 2 minutes.

**What it means:** Prometheus can't reach the exporter. Either the exporter, the host or the
network path between them is down. Other alerts for the same instance are inhibited while this
one fires, so this is usually the root cause to look at first.

**Check first**
1. Prometheus UI, **Status > Targets**: hover the error. `connection refused` means nothing is
   listening; `context deadline exceeded` means a timeout (firewall, routing, host down)
2. Is the host itself reachable? Look for a matching `ProbeFailed` alert from the ICMP probes
3. For exporters in this stack: `docker compose ps` and `docker compose logs <service>`

**Likely causes:** host rebooted or powered off, exporter service stopped, firewall rule changed,
target address changed and the file in `prometheus/targets/` wasn't updated.

**Fix:** restart the exporter (`systemctl restart node_exporter` on Linux, the
`windows_exporter` service on Windows), restore the firewall rule for the exporter port from the
Prometheus server only, or correct the target file.

**Escalate** to the owner of the host if it is unreachable and you have no access to it.

---

## HostHighCpu

**Severity:** warning. **Fires when:** CPU usage above 90% for 10 minutes (Linux and Windows).

**Check first**
1. **Host overview** dashboard: is it a sudden jump or a slow climb?
2. On the host: `top` or `htop` on Linux, Task Manager or `Get-Process | Sort-Object CPU -Desc | Select -First 10` on Windows
3. Did anything change recently: a deployment, a scheduled job, a backup window?

**Likely causes:** a runaway process, a scheduled job running longer than usual, or the host is
simply undersized for its current load.

**Fix:** stop or restart the offending process if it's misbehaving. If the load is legitimate
and persistent, the threshold or the host size needs to change, not the process.

**Escalate** if the host runs an industrial or SCADA application: don't kill processes there
without the system owner.

---

## HostHighMemory

**Severity:** warning. **Fires when:** memory usage above 90% for 10 minutes.

Linux usage is based on `MemAvailable`, so file cache does not count as used.

**Check first**
1. **Host overview** dashboard: steady climb over hours or days suggests a leak
2. On the host: `ps aux --sort=-%mem | head` on Linux, Task Manager on Windows
3. Linux: `dmesg | grep -i oom` to see whether the kernel has already killed anything

**Likely causes:** a memory leak in a long-running service, too many workers configured, or a
host that has outgrown its RAM.

**Fix:** restart the leaking service as a stopgap and raise it with its owner. Add memory or
lower worker counts for legitimate load.

---

## HostDiskWillFillIn24h

**Severity:** warning. **Fires when:** a filesystem has less than 20% free *and* the last 6 hours
of growth say it will be full within 24 hours.

**What it means:** you have time, but not much. This alert exists so disks get handled during
working hours instead of at night.

**Check first**
1. Which mountpoint or volume? It's in the alert labels
2. Linux: `du -xh --max-depth=1 <mountpoint> | sort -h | tail`; Windows: a tool like WinDirStat
   or `Get-ChildItem -Recurse | Sort-Object Length -Desc`
3. Typical suspects: logs without rotation, old backups, core dumps, application caches

**Fix:** clean up or rotate whatever is growing, then fix the cause (log rotation, retention) so
it doesn't come back. Extend the disk if growth is legitimate.

If `HostDiskAlmostFull` fires for the same disk, this warning is inhibited and that one takes over.

---

## HostDiskAlmostFull

**Severity:** critical. **Fires when:** a filesystem has less than 5% free for 5 minutes.

**What it means:** writes are about to fail. Databases, logging and the monitoring stack itself
can stop working when a disk fills.

**Check first:** same as `HostDiskWillFillIn24h`, but act now.

**Fix:** free space immediately (delete or move old logs and backups), then find the cause.
On the monitoring host itself, Prometheus storage is capped by `PROMETHEUS_RETENTION` and
`PROMETHEUS_RETENTION_SIZE` in `.env`, and container logs are capped at 3 files of 10 MB each.

---

## ProbeFailed

**Severity:** critical. **Fires when:** a blackbox probe (HTTP, ICMP, TCP or TLS) has failed for
2 minutes.

**What it means:** the target is not answering from the outside, regardless of what it reports
about itself. For OT devices without an exporter, this is often the only signal available.

**Check first**
1. Which job? `blackbox-icmp` means no ping response, `blackbox-http` an HTTP error or timeout,
   `blackbox-tls` a TLS or certificate problem
2. See exactly why it failed:
   `curl "localhost:9090/api/v1/query?query=probe_success"` or query the blackbox exporter
   directly from inside the stack:
   `docker compose exec prometheus wget -qO- "http://blackbox-exporter:9115/probe?module=icmp&target=<address>&debug=true"`
3. For `blackbox-tls`: has the certificate expired, or was it replaced with one not signed by the
   internal CA?

**Likely causes:** device powered off or disconnected, network segment down, service hung while
the host still answers ping, expired or wrongly issued certificate.

**Fix:** depends on the device. For field equipment, follow the site's procedure; for an expired
certificate, see `TLSCertExpiryCritical`.

**Escalate** to the site or device owner for OT equipment. Don't power-cycle industrial devices
from a monitoring alert without them.

---

## ProbeSlow

**Severity:** warning. **Fires when:** the average probe time over 5 minutes is above 1 second,
for 10 minutes.

**Check first**
1. **Probes and certificates** dashboard, *Probe duration*: one target or many?
2. Many targets at once usually means the network path; one target means that device or service

**Likely causes:** congested or degraded link, overloaded device, a service that's close to
failing.

**Fix:** address the network or device. Some industrial networks are slow by design; if this
target is always slow, tune the threshold for it rather than ignoring the alert.

---

## TLSCertExpiringSoon

**Severity:** warning. **Fires when:** a certificate expires within 30 days.

**What it means:** time to plan a renewal. 30 days leaves room for OT devices that can only be
changed in a maintenance window.

**Check first**
1. **Probes and certificates** dashboard: which endpoint, how many days left
2. Is renewal for this service automated? If it is, why didn't it run?

**Fix:** issue a new certificate from the internal CA and deploy it. In this lab:

    ./scripts/gen-lab-certs.sh 90 && docker compose restart tls-demo

Then check the dashboard shows the new expiry date. A renewed certificate that was never deployed
still shows the old date, because the probe checks what the service actually serves.

---

## TLSCertExpiryCritical

**Severity:** critical. **Fires when:** a certificate expires within 7 days. Inhibits
`TLSCertExpiringSoon` for the same endpoint.

**What it means:** renew now. When it expires, every client that validates it will refuse to
connect, and `ProbeFailed` will fire for the endpoint.

**Fix:** same as `TLSCertExpiringSoon`. If a maintenance window is required and none is available
in time, escalate so the owner can decide on an emergency change.

---

## Watchdog

**Always firing, by design.** It proves the path Prometheus to Alertmanager to receiver works.

**Act when it stops arriving.** Then alerting itself is broken and every other alert may be
silent. Check `docker compose ps`, then `docker compose logs alertmanager` and
`docker compose logs prometheus` for errors sending notifications.