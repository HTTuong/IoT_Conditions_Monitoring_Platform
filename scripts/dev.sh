#!/usr/bin/env bash
# Dev helper: start/stop Docker infra, backend and gateway.
# Usage: ./scripts/dev.sh {start|stop|down|restart|status|logs <backend|gateway>}
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/venv/bin/python"
RUN_DIR="$ROOT/.run"
mkdir -p "$RUN_DIR"

BACKEND_PID="$RUN_DIR/backend.pid"
GATEWAY_PID="$RUN_DIR/gateway.pid"
BACKEND_LOG="$RUN_DIR/backend.log"
GATEWAY_LOG="$RUN_DIR/gateway.log"

is_running() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

start_infra() {
  echo "Starting Docker services (Mosquitto + PostgreSQL)..."
  docker compose -f "$ROOT/docker-compose.yml" up -d
}

start_backend() {
  if is_running "$BACKEND_PID"; then
    echo "backend already running (pid $(cat "$BACKEND_PID"))"; return 0
  fi
  if lsof -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "ERROR: port 8000 is already in use by another process. Stop it first."; return 1
  fi
  echo "Starting backend..."
  (cd "$ROOT/services/backend" && nohup "$PY" -m uvicorn app.main:app --port 8000 \
      >"$BACKEND_LOG" 2>&1 & echo $! >"$BACKEND_PID")
  for _ in $(seq 1 30); do
    if curl -fs http://localhost:8000/health >/dev/null 2>&1; then
      echo "backend OK  (http://localhost:8000, log: $BACKEND_LOG)"; return 0
    fi
    sleep 1
  done
  echo "ERROR: backend did not become healthy. See $BACKEND_LOG"; return 1
}

start_gateway() {
  if is_running "$GATEWAY_PID"; then
    echo "gateway already running (pid $(cat "$GATEWAY_PID"))"; return 0
  fi
  if pgrep -f "src/gateway.py" >/dev/null 2>&1; then
    echo "ERROR: a gateway is already running outside this script (same MQTT client_id would clash). Stop it first."
    return 1
  fi
  echo "Starting gateway..."
  (cd "$ROOT/services/gateway" && nohup "$PY" -u src/gateway.py \
      >"$GATEWAY_LOG" 2>&1 & echo $! >"$GATEWAY_PID")
  for _ in $(seq 1 15); do
    if grep -q "Connected to broker" "$GATEWAY_LOG" 2>/dev/null; then
      echo "gateway OK  (log: $GATEWAY_LOG)"; return 0
    fi
    sleep 1
  done
  echo "ERROR: gateway did not connect to the broker. See $GATEWAY_LOG"; return 1
}

stop_proc() {  # $1 = name, $2 = pidfile
  if is_running "$2"; then
    local pid; pid="$(cat "$2")"
    kill "$pid" 2>/dev/null
    for _ in $(seq 1 10); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
    kill -9 "$pid" 2>/dev/null || true
    echo "$1 stopped"
  else
    echo "$1 not running"
  fi
  rm -f "$2"
}

status() {
  is_running "$BACKEND_PID" && echo "backend : running (pid $(cat "$BACKEND_PID"))" || echo "backend : stopped"
  is_running "$GATEWAY_PID" && echo "gateway : running (pid $(cat "$GATEWAY_PID"))" || echo "gateway : stopped"
  docker compose -f "$ROOT/docker-compose.yml" ps
}

case "${1:-}" in
  start)   start_infra && start_backend && start_gateway ;;
  stop)    stop_proc gateway "$GATEWAY_PID"; stop_proc backend "$BACKEND_PID" ;;
  down)    stop_proc gateway "$GATEWAY_PID"; stop_proc backend "$BACKEND_PID"
           docker compose -f "$ROOT/docker-compose.yml" stop ;;
  restart) "$0" stop; "$0" start ;;
  status)  status ;;
  logs)    tail -f "$RUN_DIR/${2:?usage: logs <backend|gateway>}.log" ;;
  *)       echo "Usage: $0 {start|stop|down|restart|status|logs <backend|gateway>}"; exit 1 ;;
esac