#!/usr/bin/env bash
set -euo pipefail

# Configuration
NAMESPACE="jenkins"
RELEASE_NAME="jenkins-service" 
LOCAL_PORT=8080
REMOTE_PORT=8080
LOG_FILE="/tmp/jenkins_pf.log"

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

status() {
  echo "[INFO] $1"
}

# Cleanup function: Kills process and deletes the temp log
cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    status "Cleaning up: stopping port-forward (PID: $PF_PID) and removing logs..."
    kill "$PF_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
}

kill_existing_pf() {
  status "Ensuring port $LOCAL_PORT is clear..."
  # Kill by pattern
  local pids
  pids=$(pgrep -f "port-forward.*${RELEASE_NAME}" || true)
  [[ -n "$pids" ]] && kill $pids 2>/dev/null || true

  # Kill anything else on the port (requires lsof)
  if command -v lsof >/dev/null; then
    local port_pid
    port_pid=$(lsof -t -i:"$LOCAL_PORT" || true)
    [[ -n "$port_pid" ]] && kill -9 "$port_pid" 2>/dev/null || true
  fi
  sleep 2
}

upgrade() {
  kill_existing_pf

  status "Starting Helm upgrade..."
  helm upgrade -f values.yaml -n "${NAMESPACE}" "${RELEASE_NAME}" jenkins/jenkins || error_exit "Helm upgrade failed"

  status "Locating controller..."
  CONTROLLER=$(kubectl get deploy,sts -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o name | head -n 1)
  [[ -z "$CONTROLLER" ]] && CONTROLLER=$(kubectl get deploy,sts -n "${NAMESPACE}" "${RELEASE_NAME}" -o name 2>/dev/null || true)

  status "Waiting for $CONTROLLER rollout..."
  kubectl rollout status -n "${NAMESPACE}" "$CONTROLLER" --timeout=300s

  status "Waiting for pods to be Ready..."
  kubectl wait --namespace "${NAMESPACE}" --for=condition=ready pod -l "app.kubernetes.io/instance=${RELEASE_NAME}" --timeout=300s

  status "Verifying EndpointSlice..."
  until kubectl get endpointslice -n "${NAMESPACE}" -l "kubernetes.io/service-name=${RELEASE_NAME}" -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | grep -q '[0-9]'; do
    sleep 2
  done

  # Ensure nginx reverse proxy is up to date
  status "Updating nginx reverse proxy configuration..."
  kubectl apply -f scripts/nginx-reverse-proxy.yaml -n "${NAMESPACE}" --validate=false || true
  kubectl rollout restart deployment/nginx-reverse-proxy -n "${NAMESPACE}" 2>/dev/null || true
  kubectl rollout status deployment/nginx-reverse-proxy -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true

  status "Starting port-forward to nginx reverse proxy..."
  trap cleanup EXIT SIGINT SIGTERM
  # Logging to a temp file helps debug if the connection drops immediately
  kubectl --namespace "${NAMESPACE}" port-forward svc/nginx-reverse-proxy 8443:443 > "$LOG_FILE" 2>&1 &
  PF_PID=$!
  
  status "Waiting for nginx reverse proxy to respond..."
  local timeout=30
  while ! curl -s -k "https://localhost:8443/health" 2>/dev/null | grep -q "healthy"; do
    if ! kill -0 "$PF_PID" 2>/dev/null; then
      echo "--- Port-Forward Error Log ---"
      cat "$LOG_FILE"
      error_exit "Port-forward process died unexpectedly."
    fi
    if (( timeout <= 0 )); then error_exit "Nginx reverse proxy failed to respond in time."; fi
    sleep 2
    (( timeout -= 2 ))
  done
  
  status "Waiting for Jenkins UI to respond at https://localhost:8443/jenkins..."
  timeout=120
  while ! curl -s -k -I "https://localhost:8443/jenkins/login" 2>/dev/null | grep -q "200\|403\|302"; do
    if ! kill -0 "$PF_PID" 2>/dev/null; then
      echo "--- Port-Forward Error Log ---"
      cat "$LOG_FILE"
      error_exit "Port-forward process died unexpectedly."
    fi
    if (( timeout <= 0 )); then error_exit "Jenkins failed to respond in time."; fi
    sleep 3
    (( timeout -= 3 ))
  done
}

open_browser() {
  local url="https://localhost:8443/jenkins"
  status "Opening Jenkins UI at: $url"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    open "$url"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if command -v xdg-open &> /dev/null; then
      xdg-open "$url"
    else
      status "💡 Open your browser and navigate to: $url"
      status "⚠️  Note: You may see a certificate warning (self-signed) - this is expected."
    fi
  fi
}

main() {
  upgrade
  status "✅ Jenkins is live! Opening browser..."
  open_browser
  
  status "Cleanup active: Press Ctrl+C to stop and clear all processes."
  while kill -0 "$PF_PID" 2>/dev/null; do
    sleep 1
  done
}

main