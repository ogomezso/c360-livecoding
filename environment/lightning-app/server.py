"""
Customer 360 — real-time view on a Lightning Table, queried over JDBC.

A tiny web server that
  * queries the Lightning Table of `c360_snapshot` with the Confluent JDBC driver (jdbc:confluent:lightning://) using a
    READ-ONLY identity,
  * serves a single-page front end that shows those rows changing live, and
  * can run `demo_changes.py` (the "Make something happen" button) with a separate, write-capable credential.

The driver is a Java library, so the server starts a JVM in-process (JPype) and calls plain JDBC: DriverManager ->
Connection -> Statement -> ResultSet. Credentials go in as connection properties (user = Global API key), never in the URL.

Lightning queries are read-only SQL on ONE table (key lookups, filters, ORDER BY, LIMIT: no joins, no aggregates), which is
exactly what a "current state of the customer" screen needs. Every query this app sends is shown in the page.

Configuration (environment):
  LIGHTNING_URL         https://sql.<region>.aws.confluent.cloud/...  (only its host is used for the JDBC URL)
  LIGHTNING_ENV_ID      environment id                      LIGHTNING_CLUSTER_ID   Kafka cluster id
  LIGHTNING_KEY/SECRET  Global API key of the read-only service account
  TABLE                 topic with the Lightning Table (default c360_snapshot)
  JDBC_JAR              path of confluent-jdbc-<version>.jar (default /opt/jdbc/confluent-jdbc-1.0.0.jar)
  DEMO_CHANGES          path of demo_changes.py (the button is hidden when the Kafka credentials are missing)
"""
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import jpype

HERE = Path(__file__).parent
PORT = int(os.environ.get("PORT", "8088"))
URL = os.environ.get("LIGHTNING_URL", "")
ENV_ID = os.environ.get("LIGHTNING_ENV_ID", "")
CLUSTER_ID = os.environ.get("LIGHTNING_CLUSTER_ID", "")
KEY = os.environ.get("LIGHTNING_KEY", "")
SECRET = os.environ.get("LIGHTNING_SECRET", "")
TABLE = os.environ.get("TABLE", "c360_snapshot")
ACTIVITY_TABLE = os.environ.get("ACTIVITY_TABLE", "")   # the fast live feed (plain producer, no Flink); empty = no feed panel
DEMO_CHANGES = os.environ.get("DEMO_CHANGES", str(HERE / "data-generation" / "producers" / "demo_changes.py"))
CHANGES_ENABLED = bool(os.environ.get("KAFKA_API_KEY") and os.environ.get("BOOTSTRAP_SERVERS") and Path(DEMO_CHANGES).exists())
JDBC_JAR = os.environ.get("JDBC_JAR", "/opt/jdbc/confluent-jdbc-1.0.0.jar")
JDBC_DRIVER = "io.confluent.jdbc.avatica.ConfluentJdbcDriver"
HOST = urllib.parse.urlparse(URL).hostname or ""
# Lightning connection: host + environment id + Kafka cluster id. The Global API key/secret are properties, not URL parameters.
JDBC_URL = f"jdbc:confluent:lightning://{HOST}?environment-id={ENV_ID}&lkc-id={CLUSTER_ID}"
ID_PATTERN = re.compile(r"^[0-9a-fA-F-]{36}$")

# The three questions the screen asks. Only what a Lightning query supports: filters, ORDER BY, LIMIT, key lookup.
SQL_LIVE = (
    "SELECT customer_id, full_name, segment, risk_band, relationship_manager, interaction_1_type, interaction_1_channel, "
    "interaction_1_ts, interaction_2_type, interaction_3_type, last_txn_merchant, last_txn_amount, txn_count "
    f"FROM {TABLE} WHERE interaction_1_ts IS NOT NULL ORDER BY interaction_1_ts DESC LIMIT 8"
)
SQL_INACTIVE = (
    "SELECT customer_id, full_name, segment, relationship_manager, total_assets "
    f"FROM {TABLE} WHERE interaction_1_type IS NULL ORDER BY total_assets DESC LIMIT 6"
)
SQL_ACTIVITY = (
    "SELECT event_id, customer_id, full_name, segment, kind, action, channel, amount, ts "
    f"FROM {ACTIVITY_TABLE} ORDER BY ts DESC LIMIT 8"
)
SQL_CARD = f"SELECT * FROM {TABLE} WHERE customer_id = '{{id}}'"

_changes_lock = threading.Lock()


class LightningError(Exception):
    def __init__(self, message, table_missing=False):
        super().__init__(message)
        self.table_missing = table_missing


_jdbc_lock = threading.Lock()
_connection = None


def _open_connection():
    """Start the JVM once, load the Confluent driver and open one read-only connection."""
    if not jpype.isJVMStarted():
        jpype.startJVM("-Xmx160m", "-Xss512k", classpath=[JDBC_JAR], convertStrings=True)
    jpype.JClass(JDBC_DRIVER)                       # registers the driver with java.sql.DriverManager
    props = jpype.JClass("java.util.Properties")()
    props.setProperty("user", KEY)                  # Global API key
    props.setProperty("password", SECRET)           # Global API secret
    return jpype.JClass("java.sql.DriverManager").getConnection(JDBC_URL, props)


def _close_quietly():
    global _connection
    try:
        if _connection is not None:
            _connection.close()
    except Exception:
        pass
    _connection = None


def _with_connection(work):
    """Run work(connection); on any failure reconnect once (keys and tables can change under a long-lived connection)."""
    global _connection
    if not (HOST and ENV_ID and CLUSTER_ID and KEY and SECRET):
        raise LightningError("Lightning credentials are not configured")
    with _jdbc_lock:
        last = None
        for _attempt in (1, 2):
            try:
                if _connection is None:
                    _connection = _open_connection()
                return work(_connection)
            except Exception as error:               # java.sql.SQLException arrives as a Python exception under JPype
                last = error
                _close_quietly()
        raise LightningError(f"JDBC: {last}")


def lightning(sql):
    """Run one query over JDBC. Returns (rows as dicts with lower-case keys, milliseconds). Values are text, like the REST API."""
    def work(connection):
        statement = connection.createStatement()
        try:
            result = statement.executeQuery(sql)
            meta = result.getMetaData()
            count = int(meta.getColumnCount())
            names = [str(meta.getColumnLabel(i + 1)).lower() for i in range(count)]
            rows = []
            while result.next():
                row = {}
                for i in range(count):
                    value = result.getString(i + 1)
                    row[names[i]] = None if result.wasNull() else str(value)
                rows.append(row)
            return rows
        finally:
            statement.close()
    started = time.perf_counter()
    rows = _with_connection(work)
    return rows, round((time.perf_counter() - started) * 1000)


def list_tables():
    """Names of the Lightning Tables this identity can query: the JDBC DatabaseMetaData (what `!tables` shows in sqlline)."""
    def work(connection):
        result = connection.getMetaData().getTables(None, None, "%", None)
        names = []
        while result.next():
            names.append(str(result.getString("TABLE_NAME")))
        return names
    return _with_connection(work)


def table_state():
    """(ready, message, names): is the Lightning Table of the topic queryable yet? names = every table this identity sees."""
    try:
        names = list_tables()
    except LightningError as error:
        text = str(error)
        if "FE_CUSTOMER_NOT_FOUND" in text or "table info not found" in text.lower():
            return False, "No Lightning Table is enabled on this cluster yet — enable one (it takes a few minutes): make lightning-enable", set()
        if "401" in text or "403" in text or "nauthorized" in text:
            return False, "The read-only API key is not accepted yet (a new key can take a couple of minutes) or lacks DeveloperRead", set()
        return False, text, set()
    lowered = {n.lower() for n in names}
    if TABLE.lower() in lowered:
        return True, "", lowered
    return False, f"No Lightning Table for '{TABLE}' yet — enable it (it takes a few minutes)", lowered


def snapshot():
    ready, message, names = table_state()
    out = {"server_time": int(time.time() * 1000), "table": TABLE, "ready": ready, "message": message}
    # The live feed is independent of the Customer 360 table: it has its own Lightning Table and shows even while the other is not ready.
    if ACTIVITY_TABLE:
        if ACTIVITY_TABLE.lower() in names:
            try:
                rows, ms = lightning(SQL_ACTIVITY)
                out["activity"] = {"ready": True, "table": ACTIVITY_TABLE, "rows": rows, "latency_ms": ms, "sql": SQL_ACTIVITY}
            except LightningError as error:
                out["activity"] = {"ready": False, "table": ACTIVITY_TABLE, "message": str(error)}
        else:
            out["activity"] = {"ready": False, "table": ACTIVITY_TABLE,
                               "message": f"The Lightning Table of {ACTIVITY_TABLE} is still being set up (a few minutes): make lightning-status"}
    if not ready:
        return out
    try:
        live, ms1 = lightning(SQL_LIVE)
        inactive, ms2 = lightning(SQL_INACTIVE)
    except LightningError as error:
        out.update(ready=False, message=str(error))
        return out
    out.update(live=live, inactive=inactive, latency_ms=max(ms1, ms2),
               sql={"live": SQL_LIVE, "inactive": SQL_INACTIVE}, jdbc_url=JDBC_URL)
    return out


def run_changes(count):
    if not CHANGES_ENABLED:
        return {"ok": False, "output": "The demo-changes credentials are not mounted in this deployment."}
    if not _changes_lock.acquire(blocking=False):
        return {"ok": False, "output": "A change is already running — wait a moment."}
    started_at = int(time.time() * 1000)
    try:
        done = subprocess.run([sys.executable, DEMO_CHANGES, "--customers", str(count)], capture_output=True, text=True, timeout=120)
        lines = [l for l in (done.stdout + done.stderr).splitlines() if l.strip() and "GETSUBSCRIPTIONS" not in l]
        ids = re.findall(r"^\s{2}([0-9a-f-]{36})\s", done.stdout, re.M)
        return {"ok": done.returncode == 0, "output": "\n".join(lines[-14:]), "customers": ids, "started_at": started_at}
    except subprocess.TimeoutExpired:
        return {"ok": False, "output": "The change took longer than 2 minutes."}
    finally:
        _changes_lock.release()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass   # quiet: the page polls every second

    def send_json(self, payload, status=200):
        data = json.dumps(payload, default=str).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path, _, query = self.path.partition("?")
        if path == "/healthz":
            return self.send_json({"ok": True})
        if path == "/api/config":
            return self.send_json({"table": TABLE, "activity_table": ACTIVITY_TABLE, "cluster": CLUSTER_ID, "environment": ENV_ID,
                                   "changes_enabled": CHANGES_ENABLED, "endpoint": URL, "access": "JDBC", "jdbc_url": JDBC_URL})
        if path == "/api/feed":      # one light query, polled fast while a change is pending
            if not ACTIVITY_TABLE:
                return self.send_json({"ready": False, "message": "no live feed configured"})
            try:
                rows, ms = lightning(SQL_ACTIVITY)
            except LightningError as error:
                return self.send_json({"ready": False, "message": str(error)})
            return self.send_json({"ready": True, "table": ACTIVITY_TABLE, "rows": rows, "latency_ms": ms, "sql": SQL_ACTIVITY, "server_time": int(time.time() * 1000)})
        if path == "/api/snapshot":
            return self.send_json(snapshot())
        if path == "/api/card":
            customer = dict(p.split("=", 1) for p in query.split("&") if "=" in p).get("id", "")
            if not ID_PATTERN.match(customer):
                return self.send_json({"error": "invalid customer id"}, 400)
            try:
                rows, ms = lightning(SQL_CARD.format(id=customer))
            except LightningError as error:
                return self.send_json({"error": str(error)}, 502)
            return self.send_json({"row": rows[0] if rows else None, "latency_ms": ms, "sql": SQL_CARD.format(id=customer)})
        if path in ("/", "/index.html"):
            data = (HERE / "static" / "index.html").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            return self.wfile.write(data)
        self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        if self.path.split("?")[0] == "/api/changes":
            return self.send_json(run_changes(3))
        self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    print(f"Customer 360 live view on http://0.0.0.0:{PORT}  (table {TABLE}, changes button {'on' if CHANGES_ENABLED else 'off'})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
