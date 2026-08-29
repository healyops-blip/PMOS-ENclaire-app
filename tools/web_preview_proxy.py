#!/usr/bin/env python3
"""Serve a Flutter Web build and proxy API requests to the remote backend."""

from __future__ import annotations

import argparse
import http.client
import json
import ssl
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar
from urllib.parse import SplitResult, urlsplit

HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}


class PreviewHandler(SimpleHTTPRequestHandler):
    backends: ClassVar[dict[str, SplitResult]] = {
        "local": urlsplit("http://127.0.0.1:8000"),
        "server": urlsplit("https://api.healy1012-ops.top"),
    }
    backend_mode: ClassVar[str] = "server"
    backend_lock: ClassVar[threading.Lock] = threading.Lock()

    @classmethod
    def _backend_state(cls) -> tuple[str, str]:
        with cls.backend_lock:
            mode = cls.backend_mode
            return mode, cls.backends[mode].geturl()

    def _send_json(self, status: int, payload: dict[str, str]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _handle_backend_state(self) -> None:
        mode, upstream = self._backend_state()
        self._send_json(200, {"mode": mode, "upstream": upstream})

    def _handle_backend_switch(self) -> None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send_json(400, {"error": "INVALID_JSON"})
            return

        mode = payload.get("mode") if isinstance(payload, dict) else None
        if mode not in self.backends:
            self._send_json(400, {"error": "INVALID_BACKEND"})
            return
        with self.backend_lock:
            type(self).backend_mode = mode
        self._handle_backend_state()

    def _is_proxy_request(self) -> bool:
        path = urlsplit(self.path).path
        return path.startswith(("/api/", "/health/"))

    def _proxy(self) -> None:
        body_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(body_length) if body_length else None
        request_headers = {
            name: value
            for name, value in self.headers.items()
            if name.lower() not in HOP_BY_HOP_HEADERS
            and name.lower() not in {"host", "content-length", "origin"}
        }
        if body is not None:
            request_headers["Content-Length"] = str(len(body))

        mode, _ = self._backend_state()
        upstream = self.backends[mode]
        if upstream.scheme == "https":
            connection = http.client.HTTPSConnection(
                upstream.hostname,
                upstream.port or 443,
                timeout=30,
                context=ssl.create_default_context(),
            )
        else:
            connection = http.client.HTTPConnection(
                upstream.hostname,
                upstream.port or 80,
                timeout=30,
            )
        try:
            connection.request(
                self.command, self.path, body=body, headers=request_headers
            )
            response = connection.getresponse()
            response_body = response.read()
            self.send_response(response.status, response.reason)
            for name, value in response.getheaders():
                if name.lower() not in HOP_BY_HOP_HEADERS | {"content-length"}:
                    self.send_header(name, value)
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(response_body)
        except (OSError, http.client.HTTPException) as error:
            message = f'{{"error":{{"code":"PROXY_ERROR","message":"{type(error).__name__}"}}}}'.encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(message)))
            self.end_headers()
            self.wfile.write(message)
        finally:
            connection.close()

    def do_GET(self) -> None:
        if urlsplit(self.path).path == "/__preview/backend":
            self._handle_backend_state()
        elif self._is_proxy_request():
            self._proxy()
        else:
            super().do_GET()

    def do_HEAD(self) -> None:
        self._proxy() if self._is_proxy_request() else super().do_HEAD()

    def do_POST(self) -> None:
        if urlsplit(self.path).path == "/__preview/backend":
            self._handle_backend_switch()
        elif self._is_proxy_request():
            self._proxy()
        else:
            self.send_error(405)

    def do_PUT(self) -> None:
        self._proxy() if self._is_proxy_request() else self.send_error(405)

    def do_DELETE(self) -> None:
        self._proxy() if self._is_proxy_request() else self.send_error(405)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--upstream", default="https://api.healy1012-ops.top")
    parser.add_argument("--local-upstream", default="http://127.0.0.1:8000")
    parser.add_argument(
        "--backend", choices=("local", "server"), default="server"
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3001)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = args.root.resolve(strict=True)
    server_upstream = urlsplit(args.upstream)
    local_upstream = urlsplit(args.local_upstream)
    if server_upstream.scheme != "https" or not server_upstream.hostname:
        raise SystemExit("--upstream must be an absolute HTTPS URL")
    if (
        local_upstream.scheme not in {"http", "https"}
        or local_upstream.hostname not in {"127.0.0.1", "localhost"}
    ):
        raise SystemExit("--local-upstream must use a loopback HTTP(S) URL")
    PreviewHandler.backends = {
        "local": local_upstream,
        "server": server_upstream,
    }
    PreviewHandler.backend_mode = args.backend

    handler = lambda *handler_args, **kwargs: PreviewHandler(
        *handler_args, directory=str(root), **kwargs
    )
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"Preview:  http://{args.host}:{args.port}")
    print(f"Local API:  {args.local_upstream}")
    print(f"Server API: {args.upstream}")
    print(f"Selected:   {args.backend}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
