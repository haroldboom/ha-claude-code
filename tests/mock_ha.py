"""Minimal stand-in for Home Assistant's REST API, for the add-on smoke test.

Token "ro-token" behaves like a system-read-only user (template render 401),
"rw-token" like a normal user, anything else is rejected.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKENS = {"ro-token", "rw-token", "supervisor-secret"}


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, body=None):
        data = json.dumps(body if body is not None else {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _token(self):
        return self.headers.get("Authorization", "").removeprefix("Bearer ")

    def do_GET(self):
        if self._token() not in TOKENS:
            return self._reply(401, {"message": "unauthorized"})
        path = self.path.split("?")[0].removeprefix("/core")
        if path == "/api/":
            return self._reply(200, {"message": "API running."})
        if path == "/api/config":
            return self._reply(200, {"version": "2026.10.0", "location_name": "Mock"})
        if path == "/api/states":
            return self._reply(200, [])
        return self._reply(404, {"message": "not found"})

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        token = self._token()
        if token not in TOKENS:
            return self._reply(401, {"message": "unauthorized"})
        if self.path.removeprefix("/core") == "/api/template":
            if token == "ro-token":
                return self._reply(401, {"message": "unauthorized"})
            self.send_response(200)
            self.send_header("Content-Length", "2")
            self.end_headers()
            return self.wfile.write(b"ok")
        return self._reply(404, {"message": "not found"})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8123), Handler).serve_forever()
