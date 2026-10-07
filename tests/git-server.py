#!/usr/bin/env python3
"""Git server for the end-to-end test: git's smart HTTP protocol through
"git http-backend", so the pipeline can clone and push (the GitOps branch).
No authentication; any user name and password are accepted.

    tests/git-server.py <root directory> <port>
"""
import http.server
import os
import socketserver
import subprocess
import sys

ROOT, PORT = sys.argv[1], int(sys.argv[2])


def read_chunked(stream):
    body = b''
    while True:
        size = int(stream.readline().strip().split(b';')[0], 16)
        if size == 0:
            stream.readline()
            return body
        body += stream.read(size)
        stream.readline()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.backend()

    def do_POST(self):
        self.backend()

    def backend(self):
        path, _, query = self.path.partition('?')
        if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
            body = read_chunked(self.rfile)
        else:
            body = self.rfile.read(int(self.headers.get('Content-Length') or 0))
        env = dict(os.environ,
                   GIT_PROJECT_ROOT=ROOT, GIT_HTTP_EXPORT_ALL='1',
                   GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='http.receivepack', GIT_CONFIG_VALUE_0='true',
                   REQUEST_METHOD=self.command, PATH_INFO=path, QUERY_STRING=query,
                   CONTENT_TYPE=self.headers.get('Content-Type', ''), CONTENT_LENGTH=str(len(body)),
                   REMOTE_USER='e2e', REMOTE_ADDR=self.client_address[0])
        if self.headers.get('Content-Encoding'):
            env['HTTP_CONTENT_ENCODING'] = self.headers['Content-Encoding']
        if self.headers.get('Git-Protocol'):
            env['GIT_PROTOCOL'] = self.headers['Git-Protocol']
        out = subprocess.run(['git', 'http-backend'], input=body, env=env, capture_output=True).stdout
        separator = b'\r\n\r\n' if b'\r\n\r\n' in out else b'\n\n'
        head, _, payload = out.partition(separator)
        status, headers = 200, []
        for line in head.decode().splitlines():
            key, _, val = line.partition(':')
            if key.lower() == 'status':
                status = int(val.split()[0])
            elif key:
                headers.append((key, val.strip()))
        self.send_response(status)
        for key, val in headers:
            self.send_header(key, val)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


Server(('0.0.0.0', PORT), Handler).serve_forever()
