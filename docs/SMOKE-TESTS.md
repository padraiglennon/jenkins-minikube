# Jenkins Smoke Tests Configuration

This setup uses JCasC and Kubernetes ConfigMaps to load Jenkins pipeline smoke tests from files in the workspace.

The smoke tests validate the three custom pod templates (RHEL9, Golang, Python-3.13) and are automatically deployed during installation.

## Files

- **[../values.yaml](../values.yaml)**: Updated Helm chart values that:
  - Reference the `smoke-tests-init-scripts` ConfigMap for initialization scripts
  - Create a `smoke-tests` folder via JCasC
  - Mount the `smoke-tests-jenkinsfiles` ConfigMap to `/var/jenkins_home/smoke-tests-jenkinsfiles`

- **[../scripts/smoke-tests-configmap.yaml](../scripts/smoke-tests-configmap.yaml)**: Kubernetes ConfigMap containing the three Jenkinsfile contents:
  - `rhel9-Jenkinsfile`: Tests RHEL 9.5 UBI container
  - `golang-Jenkinsfile`: Tests Golang container  
  - `python-3.13-Jenkinsfile`: Tests Python 3.13 container

- **[../scripts/smoke-tests-init-scripts.yaml](../scripts/smoke-tests-init-scripts.yaml)**: Kubernetes ConfigMap containing Groovy initialization script that:
  - Reads Jenkinsfiles from the mounted ConfigMap volume
  - Creates pipeline jobs in the `smoke-tests` folder
  - Runs automatically on Jenkins startup

- **[../scripts/deploy-smoke-tests.sh](../scripts/deploy-smoke-tests.sh)**: Deployment script that applies ConfigMaps and upgrades Jenkins

## Accessing Smoke Tests

Once Jenkins is deployed, access the smoke tests:

1. Navigate to **https://localhost:8443/jenkins**
2. Look for the **smoke-tests** folder in the job list
3. Each folder contains three test jobs:
   - `rhel9-test`
   - `golang-test`
   - `python-3.13-test`

## Running Smoke Tests

```bash
# Deployed automatically during install
make install

# To redeploy after changes
bash scripts/deploy-smoke-tests.sh

# Or manually:
kubectl apply -f scripts/smoke-tests-configmap.yaml -n jenkins
kubectl apply -f scripts/smoke-tests-init-scripts.yaml -n jenkins
make upgrade
```

## How It Works

1. **Initialization Script**: The `create-smoke-test-jobs.groovy` script runs during Jenkins startup via `initConfigMap`
2. **ConfigMap Mounting**: Jenkinsfiles are mounted into the pod at `/var/jenkins_home/smoke-tests-jenkinsfiles`
3. **Job Creation**: The init script reads the files and creates pipeline jobs in the `smoke-tests` folder
4. **JCasC Folder Creation**: A JCasC configuration creates the folder structure

## Deploying Smoke Tests

```bash
# Deployed automatically during install
make install

# To redeploy after changes
bash scripts/deploy-smoke-tests.sh

# Or manually:
kubectl apply -f scripts/smoke-tests-configmap.yaml -n jenkins
kubectl apply -f scripts/smoke-tests-init-scripts.yaml -n jenkins
make upgrade
```

## Test Details

### RHEL 9 Test

- **Base Image**: registry.access.redhat.com/ubi9/ubi:9.5
- **Tests**: Basic shell commands, RPM commands
- **Use Case**: RPM-based deployments

### Golang Test

- **Base Image**: golang:latest
- **Tests**: Go compilation, module verification
- **Use Case**: Go development

### Python 3.13 Test

- **Base Image**: python:3.13-slim
- **Tests**: Python execution, package management
- **Use Case**: Python development

## Advantages of This Approach

- **Lightweight values.yaml**: No inline pipeline code
- **Maintainable**: Edit Jenkinsfiles separately from Helm configuration
- **Source-controlled**: All Jenkinsfile definitions are in the workspace
- **Kubernetes-native**: Uses ConfigMaps for file management
- **Auto-loading**: Pipelines are automatically created on Jenkins startup

## After Deployment

Once Jenkins upgrades:
1. The `smoke-tests` folder will be visible in Jenkins UI
2. Three pipeline jobs will be created:
   - rhel9-smoke-test
   - golang-smoke-test
   - python-3.13-smoke-test
3. You can manually run each job to validate the pod templates work correctly
