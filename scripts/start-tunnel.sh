#!/usr/bin/env bash
set -euo pipefail

# Configuration
NAMESPACE="jenkins"
RELEASE_NAME="jenkins-service" 
LOCAL_PORT=8080
REMOTE_PORT=8080
LOG_FILE="/tmp/jenkins_tunnel.log"

status() {
  echo "[INFO] $1"
}

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

# Ensures we clean up the log and the background process on exit
cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    status "Stopping tunnel (PID: $PF_PID)..."
    kill "$PF_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
  status "Cleanup complete."
}

kill_existing_pf() {
  status "Clearing existing port $LOCAL_PORT usage..."
  local pids
  pids=$(pgrep -f "port-forward.*${RELEASE_NAME}" || true)
  [[ -n "$pids" ]] && kill $pids 2>/dev/null || true
  
  if command -v lsof >/dev/null; then
    local port_pid
    port_pid=$(lsof -t -i:"$LOCAL_PORT" || true)
    [[ -n "$port_pid" ]] && kill -9 "$port_pid" 2>/dev/null || true
  fi
}

get_password() {
  # Try to get password from the pod
  local pass
  pass=$(kubectl exec -n "${NAMESPACE}" svc/"${RELEASE_NAME}" -c jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true)
  if [[ -n "$pass" ]]; then
    echo "-------------------------------------------------------"
    echo "JENKINS ADMIN PASSWORD: $pass"
    echo "-------------------------------------------------------"
  else
    status "Note: Could not fetch password. Jenkins may still be initializing its filesystem."
  fi
}

start_tunnel() {
  kill_existing_pf
  
  status "Starting port-forward to $RELEASE_NAME..."
  trap cleanup EXIT SIGINT SIGTERM
  
  kubectl --namespace "${NAMESPACE}" port-forward svc/${RELEASE_NAME} ${LOCAL_PORT}:${REMOTE_PORT} > "$LOG_FILE" 2>&1 &
  PF_PID=$!

  status "Waiting for Jenkins to respond..."
  local timeout=60
  while ! curl -s -I "http://localhost:${LOCAL_PORT}/login" | grep -q "200\|403\|302"; do
    if ! kill -0 "$PF_PID" 2>/dev/null; then
      cat "$LOG_FILE"
      error_exit "Port-forward failed."
    fi
    (( timeout <= 0 )) && error_exit "Jenkins UI timed out."
    sleep 2
    (( timeout -= 2 ))
  done
}

main() {
  start_tunnel
  get_password
  status "✅ Tunnel is active at http://localhost:$LOCAL_PORT"
  status "Press Ctrl+C to close the tunnel and clean up."
  
  # Keep alive loop
  while kill -0 "$PF_PID" 2>/dev/null; do
    sleep 1
  done
}

main