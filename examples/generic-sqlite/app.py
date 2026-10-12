#!/usr/bin/env python3
"""Small SQLite application used to verify the generic wrapper contract."""

import json
import os
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


DB_PATH = os.environ.get("LITESTREAM_DB_PATH") or os.environ.get(
    "DB_PATH", "/var/lib/generic-sqlite/data.sqlite"
)
HOST = os.environ.get("APP_HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8080"))


def connect():
    database = Path(DB_PATH)
    database.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database)
    connection.execute(
        "CREATE TABLE IF NOT EXISTS app_state "
        "(name TEXT PRIMARY KEY, value INTEGER NOT NULL)"
    )
    connection.execute(
        "INSERT OR IGNORE INTO app_state(name, value) VALUES ('touches', 0)"
    )
    connection.commit()
    return connection


with connect() as connection:
    pass


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 - required by BaseHTTPRequestHandler
        if self.path == "/touch":
            with connect() as connection:
                connection.execute(
                    "UPDATE app_state SET value = value + 1 WHERE name = 'touches'"
                )
                connection.commit()

        if self.path not in ("/health", "/touch"):
            self.send_error(404)
            return

        with connect() as connection:
            touches = connection.execute(
                "SELECT value FROM app_state WHERE name = 'touches'"
            ).fetchone()[0]
        body = json.dumps({"status": "ok", "touches": touches}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format_string, *args):
        print("%s - - %s" % (self.address_string(), format_string % args))


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
