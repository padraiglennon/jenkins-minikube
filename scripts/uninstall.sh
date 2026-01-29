#!/usr/bin/env bash
set -euo pipefail

# Configuration
NAMESPACE="jenkins"
RELEASE_NAME="jenkins-service"
LOCAL_PORT=8080

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

status() {
  echo "[INFO] $1"
}

kill_existing_pf() {
  status "Checking for active port-forwards on port $LOCAL_PORT..."
  # 1. Kill by process pattern (specific to this release)
  local pids
  pids=$(pgrep -f "port-forward.*${RELEASE_NAME}" || true)
  if [[ -n "$pids" ]]; then
    status "Terminating port-forward processes: $pids"
    kill $pids 2>/dev/null || true
  fi

  # 2. Kill anything else on the specific local port
  if command -v lsof >/dev/null; then
    local port_pid
    port_pid=$(lsof -t -i:"$LOCAL_PORT" || true)
    if [[ -n "$port_pid" ]]; then
      status "Force clearing port $LOCAL_PORT (PID: $port_pid)"
      kill -9 "$port_pid" 2>/dev/null || true
    fi
  fi
}

uninstall_jenkins() {
  if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    status "Uninstalling Helm release '${RELEASE_NAME}'..."
    helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}"
  else
    status "Helm release '${RELEASE_NAME}' not found. Skipping."
  fi
}

uninstall_nginx() {
  status "Removing nginx reverse proxy..."
  if kubectl get deployment nginx-reverse-proxy -n "${NAMESPACE}" &>/dev/null; then
    kubectl delete -f scripts/nginx-reverse-proxy.yaml -n "${NAMESPACE}" 2>/dev/null || true
    status "Nginx reverse proxy removed."
  else
    status "Nginx reverse proxy not found. Skipping."
  fi
  
  if kubectl get secret nginx-tls -n "${NAMESPACE}" &>/dev/null; then
    kubectl delete secret nginx-tls -n "${NAMESPACE}" 2>/dev/null || true
    status "Nginx TLS secret removed."
  fi
}

delete_namespace() {
  if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    status "Deleting namespace '${NAMESPACE}' (this may take a moment)..."
    kubectl delete namespace "${NAMESPACE}" --wait=true
  else
    status "Namespace '${NAMESPACE}' does not exist. Skipping."
  fi
}

main() {
  status "🗑️ Starting full Jenkins cleanup..."
  
  # 1. Stop local processes first
  kill_existing_pf
  
  # 2. Remove Kubernetes resources
  uninstall_jenkins
  uninstall_nginx
  
  # 3. Remove PVC
  if kubectl get pvc jenkins-pvc -n "${NAMESPACE}" &>/dev/null; then
    status "Deleting PVC 'jenkins-pvc'..."
    kubectl delete pvc jenkins-pvc -n "${NAMESPACE}"
  else
    status "PVC 'jenkins-pvc' does not exist. Skipping."
  fi
  
  # 4. Delete namespace
  delete_namespace
  
  status "✅ Jenkins, namespace, PVC, and local port-forwards have been cleared."
}

main