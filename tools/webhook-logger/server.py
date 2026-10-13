"""Minimal Alertmanager webhook receiver for the lab.

Prints one line per alert so routing, grouping and inhibition can be seen in
`docker compose logs -f webhook-logger`. Standard library only, no packages to
download, which keeps it usable in an air-gapped network.
"""
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        now = datetime.now(timezone.utc).strftime("%H:%M:%S")
        receiver = self.path.strip("/") or "unknown"
        for alert in payload.get("alerts", []):
            labels = alert.get("labels", {})
            print(
                f"{now} [{receiver}] {alert.get('status', '?').upper():8} "
                f"{labels.get('alertname', '?')} "
                f"severity={labels.get('severity', '-')} "
                f"instance={labels.get('instance', '-')}",
                flush=True,
            )

        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass  # keep output to one line per alert


if __name__ == "__main__":
    print("webhook-logger listening on :8080", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()