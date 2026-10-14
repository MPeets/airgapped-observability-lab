"""HTTPS endpoint for the lab, using a certificate from the internal lab CA.

Stands in for any internal service whose certificate needs watching.
Standard library only.
"""
import ssl
from http.server import BaseHTTPRequestHandler, HTTPServer

CERT = "/certs/tls.crt"
KEY = "/certs/tls.key"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok\n")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8443), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(CERT, KEY)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    print("tls-demo listening on :8443", flush=True)
    server.serve_forever()