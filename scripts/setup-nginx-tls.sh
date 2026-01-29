#!/bin/bash

# Script to create self-signed TLS certificate for nginx reverse proxy

NAMESPACE="jenkins"
SECRET_NAME="nginx-tls"
CERT_DIR="/tmp/nginx-tls"
CERT_FILE="$CERT_DIR/tls.crt"
KEY_FILE="$CERT_DIR/tls.key"

mkdir -p "$CERT_DIR"

echo "Generating self-signed TLS certificate for localhost..."

# Generate self-signed certificate valid for 365 days
openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" \
  -days 365 -nodes \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:127.0.0.1,DNS:jenkins,IP:127.0.0.1"

if [ $? -eq 0 ]; then
  echo "✓ Certificate generated successfully"
  echo "  Certificate: $CERT_FILE"
  echo "  Key: $KEY_FILE"
  
  # Check if secret exists and delete it
  if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Deleting existing secret '$SECRET_NAME'..."
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
  fi
  
  # Create the Kubernetes secret
  echo "Creating Kubernetes secret..."
  kubectl create secret tls "$SECRET_NAME" \
    --cert="$CERT_FILE" \
    --key="$KEY_FILE" \
    -n "$NAMESPACE"
  
  if [ $? -eq 0 ]; then
    echo "✓ Secret created successfully"
    echo ""
    echo "Next steps:"
    echo "1. Deploy nginx reverse proxy: kubectl apply -f scripts/nginx-reverse-proxy.yaml"
    echo "2. Port forward: kubectl port-forward -n jenkins svc/nginx-reverse-proxy 8443:443 &"
    echo "3. Access Jenkins at: https://localhost:8443"
    echo ""
    echo "Note: Your browser will warn about the self-signed certificate - this is expected."
    echo "      Click 'Advanced' and 'Proceed' to continue."
  else
    echo "✗ Failed to create secret"
    exit 1
  fi
else
  echo "✗ Failed to generate certificate"
  exit 1
fi
