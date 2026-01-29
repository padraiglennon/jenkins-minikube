#!/usr/bin/env bash
set -euo pipefail

# Configuration
NAMESPACE="jenkins"
RELEASE_NAME="jenkins-service" 
LOCAL_PORT=8080
REMOTE_PORT=8080
LOG_FILE="/tmp/jenkins_install_pf.log"

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

status() {
  echo "[INFO] $1"
}

# Cleanup function for processes and temp files
cleanup() {
  if [[ -n "${PF_PID:-}" ]]; then
    status "Cleaning up: stopping background port-forward (PID: $PF_PID)..."
    kill "$PF_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
}

check_namespace_empty() {
  status "Verifying namespace '$NAMESPACE' is clean..."
  if kubectl get all -n "$NAMESPACE" 2>/dev/null | grep -q "NAME"; then
    error_exit "Namespace '$NAMESPACE' is not empty. Please delete the existing resources or namespace before a fresh install."
  fi
}

check_kubectl_connection() {
  status "Verifying kubectl connection to cluster..."
  if ! kubectl cluster-info &>/dev/null; then
    error_exit "Cannot connect to Kubernetes cluster. Please ensure your cluster is running and kubectl is configured."
  fi
}

ensure_minikube_running() {
  # Check if minikube is installed
  if ! command -v minikube &> /dev/null; then
    status "Minikube not found. Assuming external cluster is being used."
    return 0
  fi

  # Check if minikube is already running
  local minikube_status
  minikube_status=$(minikube status --format={{.Host}} 2>/dev/null || echo "Stopped")
  
  if [[ "$minikube_status" == "Running" ]]; then
    status "Minikube is already running."
    return 0
  fi

  # Start minikube if it's not running
  status "Starting minikube..."
  minikube start || error_exit "Failed to start minikube"
  sleep 5  # Give minikube time to fully initialize
  status "✅ Minikube started successfully"
}

kill_existing_pf() {
  status "Clearing port $LOCAL_PORT..."
  local pids
  pids=$(pgrep -f "port-forward.*${RELEASE_NAME}" || true)
  [[ -n "$pids" ]] && kill $pids 2>/dev/null || true
  
  if command -v lsof >/dev/null; then
    local port_pid
    port_pid=$(lsof -t -i:"$LOCAL_PORT" || true)
    [[ -n "$port_pid" ]] && kill -9 "$port_pid" 2>/dev/null || true
  fi
  sleep 1
}

get_admin_password() {
  status "Retrieving Initial Admin Password..."
  # Wait a moment for the file to exist on the new disk
  sleep 5
  local password
  password=$(kubectl exec -n "${NAMESPACE}" svc/"${RELEASE_NAME}" -c jenkins -- cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Could not retrieve yet. You can find it in the pod at /var/jenkins_home/secrets/initialAdminPassword")
  echo -e "\n-------------------------------------------------------"
  echo "JENKINS ADMIN PASSWORD: $password"
  echo "-------------------------------------------------------\n"
}

install_jenkins() {
  # 1. Pre-flight checks
  [[ -f "values.yaml" ]] || error_exit "values.yaml not found in current directory."
  ensure_minikube_running
  check_kubectl_connection
  check_namespace_empty
  kill_existing_pf

  # 2. Create namespace
  status "Creating namespace ${NAMESPACE}..."
  kubectl create namespace "${NAMESPACE}" 2>/dev/null || true

  # 3. Create PVC for Jenkins agents
  status "Creating PVC for Jenkins agents..."
  kubectl apply -f scripts/jenkins-pvc.yaml -n "${NAMESPACE}" --validate=false || error_exit "Failed to create jenkins-pvc"

  # 3a. Create admin password secret
  status "Creating Jenkins admin password secret..."
  if ! kubectl get secret jenkins-admin-password -n "${NAMESPACE}" &>/dev/null; then
    echo ""
    read -sp "Enter Jenkins admin password: " admin_password
    echo ""
    read -sp "Confirm password: " admin_password_confirm
    echo ""
    
    if [ "$admin_password" != "$admin_password_confirm" ]; then
      error_exit "Passwords do not match"
    fi
    
    if [ -z "$admin_password" ]; then
      error_exit "Password cannot be empty"
    fi
    
    kubectl create secret generic jenkins-admin-password \
      --from-literal=password="$admin_password" \
      -n "${NAMESPACE}" || error_exit "Failed to create admin password secret"
    status "✓ Admin password secret created"
  else
    status "Admin password secret already exists, skipping creation"
  fi

  # 3b. Initialize PVC with required folder structure
  status "Initializing PVC with controller and agent folders..."
  kubectl apply -f scripts/jenkins-pvc-init-job.yaml -n "${NAMESPACE}" --validate=false || error_exit "Failed to create init job"
  
  # Wait for init job to complete
  status "Waiting for PVC initialization to complete..."
  kubectl wait --for=condition=complete job/jenkins-pvc-init -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true
  
  # Clean up init job
  kubectl delete job jenkins-pvc-init -n "${NAMESPACE}" 2>/dev/null || true

  # 4. Create ConfigMaps for smoke tests
  status "Creating smoke-tests ConfigMaps..."
  kubectl apply -f scripts/smoke-tests-configmap.yaml -n "${NAMESPACE}" --validate=false || error_exit "Failed to create smoke-tests-configmap"
  kubectl apply -f scripts/smoke-tests-init-scripts.yaml -n "${NAMESPACE}" --validate=false || error_exit "Failed to create smoke-tests-init-scripts"

  # 4b. Setup nginx reverse proxy with TLS
  status "Setting up nginx reverse proxy with TLS..."
  bash scripts/setup-nginx-tls.sh || error_exit "Failed to setup nginx TLS"
  
  status "Deploying nginx reverse proxy..."
  kubectl apply -f scripts/nginx-reverse-proxy.yaml -n "${NAMESPACE}" --validate=false || error_exit "Failed to deploy nginx"
  
  # Restart nginx to pick up the new ConfigMap
  status "Restarting nginx reverse proxy to apply configuration..."
  kubectl rollout restart deployment/nginx-reverse-proxy -n "${NAMESPACE}" 2>/dev/null || true
  
  # Wait for nginx to be ready
  status "Waiting for nginx reverse proxy to be ready..."
  kubectl rollout status deployment/nginx-reverse-proxy -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true

  # 5. Repo Management
  status "Updating Helm repositories..."
  helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
  helm repo update > /dev/null

  # 6. Installation
  status "Installing Jenkins release: ${RELEASE_NAME}..."
  helm install "${RELEASE_NAME}" -n "${NAMESPACE}" --create-namespace jenkins/jenkins

  # 7. Apply custom configuration immediately
  status "Applying values.yaml configuration..."
  helm upgrade -f values.yaml -n "${NAMESPACE}" "${RELEASE_NAME}" jenkins/jenkins

  # 8. Wait for Controller (Deployment or StatefulSet)
  status "Locating controller and waiting for rollout..."
  CONTROLLER=$(kubectl get deploy,sts -n "${NAMESPACE}" -l "app.kubernetes.io/instance=${RELEASE_NAME}" -o name | head -n 1)
  [[ -z "$CONTROLLER" ]] && CONTROLLER=$(kubectl get deploy,sts -n "${NAMESPACE}" "${RELEASE_NAME}" -o name 2>/dev/null || true)
  
  kubectl rollout status -n "${NAMESPACE}" "$CONTROLLER" --timeout=300s

  # 9. Verify Network Readiness
  status "Verifying EndpointSlice..."
  until kubectl get endpointslice -n "${NAMESPACE}" -l "kubernetes.io/service-name=${RELEASE_NAME}" -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | grep -q '[0-9]'; do
    sleep 2
  done

  # 10. Start Port-Forwarding to nginx reverse proxy
  status "Starting port-forward to nginx reverse proxy..."
  trap cleanup EXIT SIGINT SIGTERM
  kubectl --namespace "${NAMESPACE}" port-forward svc/nginx-reverse-proxy 8443:443 > "$LOG_FILE" 2>&1 &
  PF_PID=$!

  # 11. Health Check (via nginx health endpoint)
  status "Waiting for nginx reverse proxy to respond..."
  local timeout=30
  while ! curl -s -k "https://localhost:8443/health" 2>/dev/null | grep -q "healthy"; do
    if ! kill -0 "$PF_PID" 2>/dev/null; then
      cat "$LOG_FILE"
      error_exit "Port-forward failed during initialization."
    fi
    (( timeout <= 0 )) && error_exit "Nginx reverse proxy timed out during startup."
    sleep 2
    (( timeout -= 2 ))
  done
  
  status "Waiting for Jenkins UI to respond (this takes a moment for the first boot)..."
  timeout=180 # Longer timeout for first-time plugin initialization
  while ! curl -s -k -I "https://localhost:8443/jenkins/login" 2>/dev/null | grep -q "200\|403\|302"; do
    if ! kill -0 "$PF_PID" 2>/dev/null; then
      cat "$LOG_FILE"
      error_exit "Port-forward failed during initialization."
    fi
    (( timeout <= 0 )) && error_exit "Jenkins timed out during first boot."
    sleep 5
    (( timeout -= 5 ))
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
  install_jenkins
  get_admin_password
  status "✅ Installation complete! Opening browser..."
  open_browser
  
  status "Cleanup active: Port-forwarding will stop when you press Ctrl+C."
  while kill -0 "$PF_PID" 2>/dev/null; do
    sleep 1
  done
}

main