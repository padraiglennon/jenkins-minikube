#!/bin/bash

# Helper script to manage nginx reverse proxy

set -e

NAMESPACE="jenkins"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: $0 {setup|deploy|remove|status}"
  echo ""
  echo "Commands:"
  echo "  setup    - Generate self-signed TLS certificate"
  echo "  deploy   - Deploy nginx reverse proxy"
  echo "  remove   - Remove nginx reverse proxy"
  echo "  status   - Show nginx deployment status"
  exit 1
}

setup_tls() {
  echo "Setting up TLS certificate..."
  "$SCRIPT_DIR/setup-nginx-tls.sh"
}

deploy_proxy() {
  echo "Deploying nginx reverse proxy..."
  kubectl apply -f "$SCRIPT_DIR/nginx-reverse-proxy.yaml"
  echo "✓ Nginx reverse proxy deployed"
  echo ""
  echo "Port forwarding options:"
  echo "1. Manual: kubectl port-forward -n jenkins svc/nginx-reverse-proxy 8443:443"
  echo "2. Background: kubectl port-forward -n jenkins svc/nginx-reverse-proxy 8443:443 &"
  echo ""
  echo "Access Jenkins at: https://localhost:8443"
}

remove_proxy() {
  echo "Removing nginx reverse proxy..."
  kubectl delete -f "$SCRIPT_DIR/nginx-reverse-proxy.yaml" || true
  kubectl delete secret nginx-tls -n "$NAMESPACE" || true
  echo "✓ Nginx reverse proxy removed"
}

show_status() {
  echo "Nginx reverse proxy status:"
  echo ""
  kubectl get deployment,service,configmap,secret -n "$NAMESPACE" \
    -l app=nginx-reverse-proxy 2>/dev/null || echo "Nginx not deployed"
  echo ""
  echo "Pods:"
  kubectl get pods -n "$NAMESPACE" -l app=nginx-reverse-proxy || echo "No nginx pods found"
}

case "${1:-}" in
  setup)
    setup_tls
    ;;
  deploy)
    deploy_proxy
    ;;
  remove)
    remove_proxy
    ;;
  status)
    show_status
    ;;
  *)
    usage
    ;;
esac
