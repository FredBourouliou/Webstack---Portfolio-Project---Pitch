#!/usr/bin/env python3
"""Local dev server. Static files from web/, CGI from bin/.
Usage: python3 scripts/dev-server.py [port]
"""
from __future__ import annotations

import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "web"
CGI_DIR = ROOT / "bin"
PDF_DIR = ROOT / "pdf"

MIME = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".ico": "image/x-icon",
    ".png": "image/png",
    ".svg": "image/svg+xml",
    ".pdf": "application/pdf",
}


class CobillHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.command, fmt % args))

    def _dispatch(self, method: str) -> None:
        parts = urlsplit(self.path)
        path = parts.path
        if path.startswith("/cgi-bin/"):
            self._run_cgi(method, path[len("/cgi-bin/"):], parts.query)
        elif path.startswith("/pdf/"):
            self._serve_from(PDF_DIR, path[len("/pdf/"):])
        else:
            self._serve_static(path)

    def _serve_from(self, base: Path, rel: str) -> None:
        target = (base / rel).resolve()
        base_resolved = base.resolve()
        if base_resolved not in target.parents and target != base_resolved:
            self.send_error(403, "Forbidden")
            return
        if not target.is_file():
            self.send_error(404, "Not Found")
            return
        ctype = MIME.get(target.suffix.lower(), "application/octet-stream")
        body = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _serve_static(self, path: str) -> None:
        if path in ("", "/"):
            path = "/index.html"
        target = (WEB_DIR / path.lstrip("/")).resolve()
        if WEB_DIR.resolve() not in target.parents and target != WEB_DIR.resolve():
            self.send_error(403, "Forbidden")
            return
        if not target.is_file():
            self.send_error(404, "Not Found")
            return
        ctype = MIME.get(target.suffix.lower(), "application/octet-stream")
        body = target.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _run_cgi(self, method: str, name: str, query: str) -> None:
        binary = (CGI_DIR / name).resolve()
        if CGI_DIR.resolve() != binary.parent or not binary.is_file():
            self.send_error(404, "CGI not found: %s" % name)
            return
        if not os.access(binary, os.X_OK):
            self.send_error(500, "CGI not executable: %s" % name)
            return

        body = b""
        if method == "POST":
            length = int(self.headers.get("Content-Length", "0") or "0")
            if length:
                body = self.rfile.read(length)

        env = os.environ.copy()
        env.update({
            "GATEWAY_INTERFACE": "CGI/1.1",
            "SERVER_PROTOCOL": self.protocol_version,
            "REQUEST_METHOD": method,
            "QUERY_STRING": query or "",
            "CONTENT_LENGTH": str(len(body)),
            "CONTENT_TYPE": self.headers.get(
                "Content-Type", "application/x-www-form-urlencoded"
            ),
            "SCRIPT_NAME": "/cgi-bin/" + name,
            "REMOTE_ADDR": self.client_address[0],
        })
        # CGI/1.1: surface every request header as HTTP_<UPPER_NAME>.
        for header_name, header_value in self.headers.items():
            key = "HTTP_" + header_name.upper().replace("-", "_")
            env[key] = header_value

        try:
            proc = subprocess.run(
                [str(binary)],
                input=body,
                env=env,
                cwd=str(ROOT),
                capture_output=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            self.send_error(504, "CGI timeout")
            return

        if proc.returncode != 0:
            sys.stderr.write(
                "CGI %s exit=%d stderr=%s\n"
                % (name, proc.returncode, proc.stderr.decode("utf-8", "replace"))
            )

        # Parse CGI headers from stdout (separated from body by blank line).
        headers, _, payload = proc.stdout.partition(b"\r\n\r\n")
        if not payload:
            headers, _, payload = proc.stdout.partition(b"\n\n")
        if not payload and headers:
            # COBOL DISPLAY emits LF-terminated lines; "Content-Type: ...\n \n"
            # produces a single-space line between header and body.
            headers, _, payload = proc.stdout.partition(b"\n \n")

        status = 200
        out_headers = []
        for line in headers.splitlines():
            if not line.strip():
                continue
            line = line.decode("latin-1").rstrip()
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip()
            if k.lower() == "status":
                try:
                    status = int(v.split()[0])
                except ValueError:
                    pass
                continue
            out_headers.append((k, v))

        self.send_response(status)
        for k, v in out_headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    addr = ("127.0.0.1", port)
    print("COBILL dev server")
    print("  web : %s" % WEB_DIR)
    print("  cgi : %s" % CGI_DIR)
    print("  url : http://%s:%d/" % addr)
    server = ThreadingHTTPServer(addr, CobillHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
    return 0


if __name__ == "__main__":
    sys.exit(main())
