#!/bin/bash

# Script to manage Jenkins admin password via Kubernetes secret

NAMESPACE="jenkins"
SECRET_NAME="jenkins-admin-password"

usage() {
  echo "Usage: $0 {create|update|get|delete}"
  echo ""
  echo "Commands:"
  echo "  create  - Create secret with new password (will prompt)"
  echo "  update  - Update existing secret password (will prompt)"
  echo "  get     - Display current password"
  echo "  delete  - Delete the secret"
  exit 1
}

create_secret() {
  if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "✗ Secret '$SECRET_NAME' already exists"
    echo "Use: $0 update"
    exit 1
  fi
  
  read -sp "Enter Jenkins admin password: " password
  echo ""
  read -sp "Confirm password: " password_confirm
  echo ""
  
  if [ "$password" != "$password_confirm" ]; then
    echo "✗ Passwords do not match"
    exit 1
  fi
  
  if [ -z "$password" ]; then
    echo "✗ Password cannot be empty"
    exit 1
  fi
  
  kubectl create secret generic "$SECRET_NAME" \
    --from-literal=password="$password" \
    -n "$NAMESPACE"
  
  if [ $? -eq 0 ]; then
    echo "✓ Secret created successfully"
    echo "  Secret: $SECRET_NAME"
    echo "  Namespace: $NAMESPACE"
  else
    echo "✗ Failed to create secret"
    exit 1
  fi
}

update_secret() {
  if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "✗ Secret '$SECRET_NAME' does not exist"
    echo "Use: $0 create"
    exit 1
  fi
  
  read -sp "Enter new Jenkins admin password: " password
  echo ""
  read -sp "Confirm password: " password_confirm
  echo ""
  
  if [ "$password" != "$password_confirm" ]; then
    echo "✗ Passwords do not match"
    exit 1
  fi
  
  if [ -z "$password" ]; then
    echo "✗ Password cannot be empty"
    exit 1
  fi
  
  kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
  kubectl create secret generic "$SECRET_NAME" \
    --from-literal=password="$password" \
    -n "$NAMESPACE"
  
  if [ $? -eq 0 ]; then
    echo "✓ Secret updated successfully"
    echo "  Note: Jenkins will need to be restarted to apply the new password"
    echo "  Run: helm upgrade -f values.yaml -n $NAMESPACE jenkins-service jenkins/jenkins"
  else
    echo "✗ Failed to update secret"
    exit 1
  fi
}

get_password() {
  if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "✗ Secret '$SECRET_NAME' does not exist"
    exit 1
  fi
  
  password=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
  echo "Jenkins admin password: $password"
}

delete_secret() {
  if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "✗ Secret '$SECRET_NAME' does not exist"
    exit 1
  fi
  
  read -p "Delete secret '$SECRET_NAME'? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
  fi
  
  kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
  if [ $? -eq 0 ]; then
    echo "✓ Secret deleted"
  else
    echo "✗ Failed to delete secret"
    exit 1
  fi
}

case "${1:-}" in
  create)
    create_secret
    ;;
  update)
    update_secret
    ;;
  get)
    get_password
    ;;
  delete)
    delete_secret
    ;;
  *)
    usage
    ;;
esac
