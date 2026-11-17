#!/usr/bin/env python3
"""Tiny file server for the recoveryOS stage 1 script: GET serves the directory, PUT stores a file (backups).
   upload-server.py <dir> <port>"""
import http.server, os, sys
D, P = sys.argv[1], int(sys.argv[2])
os.chdir(D)
class H(http.server.SimpleHTTPRequestHandler):
    def do_PUT(self):
        n = os.path.basename(self.path)
        if not n or n.startswith('.'): self.send_error(400); return
        data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        open(n, 'wb').write(data); self.send_response(201); self.end_headers()
http.server.ThreadingHTTPServer(('', P), H).serve_forever()
