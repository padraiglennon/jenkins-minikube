#!/bin/bash

# Deploy smoke-tests ConfigMaps and update Jenkins
set -e

NAMESPACE="jenkins"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[INFO] Applying smoke-tests ConfigMaps..."

# Apply the Jenkinsfiles ConfigMap
kubectl apply -f "${SCRIPT_DIR}/scripts/smoke-tests-configmap.yaml" -n ${NAMESPACE}

# Apply the init scripts ConfigMap
kubectl apply -f "${SCRIPT_DIR}/scripts/smoke-tests-init-scripts.yaml" -n ${NAMESPACE}

echo "[INFO] ConfigMaps deployed. Updating Jenkins Helm release..."

# Upgrade Jenkins with the new configuration
make upgrade

echo "[INFO] Jenkins upgrade completed with smoke-tests folder and ConfigMap-loaded jobs"
