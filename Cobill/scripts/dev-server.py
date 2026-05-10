#!/usr/bin/env python3
"""Local dev server for Le Cobol.

Serves the same routes the production Apache vhost exposes:
  - /                static files from web/
  - /cgi-bin/<name>  fork a COBOL binary from bin/ and treat
                     its stdout as a CGI response
  - /pdf/<file>      static files from pdf/ (generated PDFs)

The script intentionally mirrors Apache's mod_cgi protocol so a
binary that runs here will also run on the deployed server. CGI
contract: pass request data through environment variables and
stdin, parse stdout into headers + body.

Usage:
    python3 scripts/dev-server.py            # listen on :8080
    python3 scripts/dev-server.py 9000       # listen on :9000

Not for production: no TLS, no auth in front, no rate limiting,
no privilege drop, threading is naive. Apache + mod_cgi handles
all of that in deploy.
"""
from __future__ import annotations

import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

# All paths are resolved from the Cobill/ project root so the
# script can be invoked from anywhere.
ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "web"
CGI_DIR = ROOT / "bin"
PDF_DIR = ROOT / "pdf"

# Minimal MIME table. Anything unmapped falls back to
# application/octet-stream below.
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
    """Three-way router: CGI, generated PDFs, static files."""

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def log_message(self, fmt, *args):
        # Override the default "127.0.0.1 - - [date]" log format
        # for something terser. Goes to stderr to keep stdout
        # clean for piping.
        sys.stderr.write("[%s] %s\n" % (self.command, fmt % args))

    def _dispatch(self, method: str) -> None:
        parts = urlsplit(self.path)
        path = parts.path
        if path.startswith("/cgi-bin/"):
            # Strip the prefix; the rest is the binary name.
            self._run_cgi(method, path[len("/cgi-bin/"):], parts.query)
        elif path.startswith("/pdf/"):
            self._serve_from(PDF_DIR, path[len("/pdf/"):])
        else:
            self._serve_static(path)

    def _serve_from(self, base: Path, rel: str) -> None:
        """Static file served from `base`, with path traversal guard."""
        target = (base / rel).resolve()
        base_resolved = base.resolve()
        # The resolved target must live inside `base` (or be
        # `base` itself for "/"). Anything else is an attempt at
        # path traversal via .. segments or symlinks.
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
        """Serve a file out of web/. "/" maps to index.html."""
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
        """Fork a COBOL binary and surface its CGI response.

        Implements just enough of RFC 3875 (CGI/1.1) for the
        binaries built from this repo:
          - REQUEST_METHOD / QUERY_STRING / CONTENT_LENGTH
          - Standard input = POST body (raw bytes)
          - Standard output = headers + blank line + body
          - HTTP_* environment for each request header
        """
        # Resolve the binary inside bin/, refuse anything that
        # tries to escape that directory.
        binary = (CGI_DIR / name).resolve()
        if CGI_DIR.resolve() != binary.parent or not binary.is_file():
            self.send_error(404, "CGI not found: %s" % name)
            return
        if not os.access(binary, os.X_OK):
            self.send_error(500, "CGI not executable: %s" % name)
            return

        # Read the POST body verbatim. GET requests have no body
        # and Content-Length is absent / zero.
        body = b""
        if method == "POST":
            length = int(self.headers.get("Content-Length", "0") or "0")
            if length:
                body = self.rfile.read(length)

        # Build the CGI environment. Inherit the current shell
        # env so things like COBILL_AUTH_HASH set via direnv or
        # the Makefile reach the binary.
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
        # CGI/1.1 surfaces every request header as HTTP_<UPPER_NAME>
        # with dashes turned into underscores. auth-check.cpy
        # reads HTTP_COOKIE and HTTP_HX_REQUEST through this
        # mechanism.
        for header_name, header_value in self.headers.items():
            key = "HTTP_" + header_name.upper().replace("-", "_")
            env[key] = header_value

        # Run the binary with the POST body piped to its stdin
        # and a 10 second hard timeout (matches Apache defaults).
        # cwd=ROOT so the binary finds data/, pdf/, lib/ at the
        # relative paths used in the SELECT clauses.
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
            # Surface CGI errors to the dev terminal but still
            # try to parse a partial response. Apache does the
            # same thing.
            sys.stderr.write(
                "CGI %s exit=%d stderr=%s\n"
                % (name, proc.returncode, proc.stderr.decode("utf-8", "replace"))
            )

        # The CGI spec says headers and body are separated by a
        # blank line. The standard separator is CRLF CRLF, but
        # COBOL DISPLAY emits plain LF; we try several variants.
        headers, _, payload = proc.stdout.partition(b"\r\n\r\n")
        if not payload:
            headers, _, payload = proc.stdout.partition(b"\n\n")
        if not payload and headers:
            # Some COBOL programs emit "Content-Type: ...\n \n",
            # i.e. a single-space line as the separator. Match
            # that too rather than fight it in the COBOL side.
            headers, _, payload = proc.stdout.partition(b"\n \n")

        # Parse the headers. "Status: NNN" is the CGI way to set
        # the response status code; everything else passes
        # through verbatim.
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
        # Force a Content-Length so HTTP/1.1 keep-alive works
        # even if the CGI binary forgot to set one.
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> int:
    # Single positional argument: port number, defaults to 8080.
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
