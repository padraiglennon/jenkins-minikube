# Jenkins Kubernetes Deployment

Custom Jenkins Helm deployment with nginx reverse proxy, TLS encryption, pod templates, smoke tests, and infrastructure-as-code configuration.

## Directory Structure

```
.
├── docs/                          # Documentation
│   ├── NGINX-REVERSE-PROXY.md    # Nginx reverse proxy setup
│   ├── ADMIN-PASSWORD.md         # Admin password management
│   └── SMOKE-TESTS.md            # Smoke test configuration guide
├── jcasc/                         # Jenkins Configuration as Code
│   └── README.md                 # JCasC setup and reference
├── scripts/                       # Kubernetes manifests and scripts
│   ├── install.sh                # Install Jenkins
│   ├── upgrade.sh                # Upgrade Jenkins
│   ├── uninstall.sh              # Uninstall Jenkins
│   ├── start-tunnel.sh           # Start port-forward tunnel
│   ├── deploy-smoke-tests.sh     # Deploy smoke tests
│   ├── manage-admin-password.sh  # Admin password management
│   ├── manage-nginx.sh           # Nginx management
│   ├── setup-nginx-tls.sh        # Generate TLS certificates
│   ├── nginx-reverse-proxy.yaml  # Nginx reverse proxy deployment
│   ├── jenkins-pvc-init-job.yaml # PVC initialization
│   ├── smoke-tests-configmap.yaml # Jenkinsfile definitions
│   └── smoke-tests-init-scripts.yaml # Job initialization
├── smoke-tests/                   # Pipeline test files
│   ├── rhel9-Jenkinsfile
│   ├── golang-Jenkinsfile
│   └── python-3.13-Jenkinsfile
├── values.yaml                    # Helm values configuration
├── Makefile                       # Build automation
└── README.md                      # This file
```

## Quick Start

### Prerequisites
- Kubernetes cluster with Helm 3.x
- kubectl configured to your cluster
- docker (for local testing)

### Installation

```bash
# Install Jenkins with nginx reverse proxy and TLS
make install

# You will be prompted for Jenkins admin password (stored in Kubernetes secret)
```

### Access Jenkins

Jenkins is now available at: **https://localhost:8443/jenkins**

**Note:** Your browser will warn about the self-signed certificate - this is expected. Click "Advanced" → "Proceed".

### Admin Password

Your password is stored in a Kubernetes secret:

```bash
make password-get     # Retrieve password
make password-set     # Change password
```

### Upgrade Deployment

```bash
make upgrade
```

### Uninstall

```bash
make uninstall
```

## Configuration

### Pod Templates

The deployment includes three custom Kubernetes pod templates:

- **rhel9**: RHEL 9.5 UBI container for RPM-based builds
- **golang**: Go 1.21 container for Go development
- **python-3.13**: Python 3.13 container for Python development

See [values.yaml](values.yaml) `agent.podTemplates` section for details.

### JCasC Configuration

Jenkins Configuration as Code is stored in [values.yaml](values.yaml) under `controller.JCasC`.

See [jcasc/README.md](jcasc/README.md) for detailed documentation.

### Smoke Tests

Automated smoke tests validate the pod template configurations.

See [docs/SMOKE-TESTS.md](docs/SMOKE-TESTS.md) for details.

## Key Features

- **Pod Templates**: Three custom Kubernetes pod templates with different base images
- **JCasC**: Infrastructure-as-code configuration management
- **Auto-reloading**: JCasC configuration reloads without restart
- **Smoke Tests**: Automated pipeline tests for pod templates
- **Persistence**: PVC-backed Jenkins home directory
- **RBAC**: Properly configured service accounts and permissions

## Plugins

- kubernetes: Kubernetes plugin for pod-based agents
- workflow-aggregator: Pipeline support
- git: Git integration
- configuration-as-code: JCasC support
- docker-workflow: Docker integration
- metrics: Prometheus metrics
- pipeline-graph-view: Pipeline visualization

## Troubleshooting

### Pod Template Not Being Used

```bash
# Check if default agent is disabled
kubectl get cm jenkins-jenkins-jcasc-config -n jenkins -o yaml | grep disableDefaultAgent
```

### ConfigMap Not Mounting

```bash
# Verify volume mounts in pod
kubectl get pod -n jenkins -o yaml | grep -A 5 volumeMounts
```

### JCasC Errors

```bash
# Check Jenkins logs
kubectl logs -f -n jenkins -l app.kubernetes.io/name=jenkins
```

## Additional Commands

```bash
# View Jenkins logs
make logs

# Port-forward to Jenkins
make start-tunnel

# SSH into Jenkins pod (if configured)
kubectl exec -it -n jenkins <pod-name> -- bash
```

## Contributing

To modify this deployment:

1. Edit [values.yaml](values.yaml) for Helm configuration
2. Edit files in [jcasc/](jcasc/) or [scripts/](scripts/) for specific configurations
3. Edit [docs/](docs/) for documentation updates
4. Run `make upgrade` to apply changes

## License

See LICENSE file for details
