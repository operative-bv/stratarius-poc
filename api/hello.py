from http.server import BaseHTTPRequestHandler
import json
import sys
import platform


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        payload = {
            "status": "ok",
            "runtime": "python",
            "python_version": sys.version,
            "platform": platform.platform(),
        }
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode())
