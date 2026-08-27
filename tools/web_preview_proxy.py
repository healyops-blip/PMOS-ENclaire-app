#!/usr/bin/env python3
"""Serve a Flutter Web build and proxy API requests to the remote backend."""

from __future__ import annotations

import argparse
import http.client
import ssl
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

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
    upstream = urlsplit("https://api.healy1012-ops.top")

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

        connection = http.client.HTTPSConnection(
            self.upstream.hostname,
            self.upstream.port or 443,
            timeout=30,
            context=ssl.create_default_context(),
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
        self._proxy() if self._is_proxy_request() else super().do_GET()

    def do_HEAD(self) -> None:
        self._proxy() if self._is_proxy_request() else super().do_HEAD()

    def do_POST(self) -> None:
        self._proxy() if self._is_proxy_request() else self.send_error(405)

    def do_PUT(self) -> None:
        self._proxy() if self._is_proxy_request() else self.send_error(405)

    def do_DELETE(self) -> None:
        self._proxy() if self._is_proxy_request() else self.send_error(405)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--upstream", default="https://api.healy1012-ops.top")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3001)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = args.root.resolve(strict=True)
    PreviewHandler.upstream = urlsplit(args.upstream)
    if (
        PreviewHandler.upstream.scheme != "https"
        or not PreviewHandler.upstream.hostname
    ):
        raise SystemExit("--upstream must be an absolute HTTPS URL")

    handler = lambda *handler_args, **kwargs: PreviewHandler(
        *handler_args, directory=str(root), **kwargs
    )
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"Preview:  http://{args.host}:{args.port}")
    print(f"API proxy: /api/* -> {args.upstream}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
