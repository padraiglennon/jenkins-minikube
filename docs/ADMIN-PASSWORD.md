# Jenkins Admin Password Management

The Jenkins admin password is managed via Kubernetes secrets, ensuring it persists across cluster restarts and is never hardcoded in configuration files.

## Overview

- **Storage**: Kubernetes secret `jenkins-admin-password`
- **Key Name**: `password`
- **Namespace**: jenkins
- **Persistence**: Secret data persists when cluster restarts
- **Security**: Password managed through script interface, never visible in logs

## Quick Start

### Initial Setup (First Install)

When you run `make install`, you'll be prompted to set the admin password:

```
Enter Jenkins admin password: ••••••••
Confirm password: ••••••••
✓ Admin password secret created
```

The password is stored in Kubernetes and used by Jenkins via JCasC configuration.

### Retrieve Current Password

```bash
make password-get
```

Output:
```
Jenkins admin password: your_password_here
```

### Change Password

```bash
make password-set
```

This will:
1. Prompt for new password
2. Update the Kubernetes secret
3. **Note**: Jenkins will need to be restarted to apply the new password
   ```bash
   make redeploy
   ```

### Create Password Secret Manually

If the secret is missing or deleted:

```bash
make password-create
```

This will prompt for a password and create the secret.

### Delete Password Secret

To remove the secret (careful - this will break Jenkins auth):

```bash
bash scripts/manage-admin-password.sh delete
```

You'll need to confirm the deletion.

## How It Works

### Kubernetes Integration

The password is stored as a Kubernetes Generic secret:

```bash
# Manually view the secret (encoded)
kubectl get secret jenkins-admin-password -n jenkins -o yaml

# Manually view decoded password
kubectl get secret jenkins-admin-password -n jenkins -o jsonpath='{.data.password}' | base64 -d
```

### Jenkins Integration

Jenkins reads the password through JCasC configuration:

1. `values.yaml` specifies: `password: "${jenkins-admin-password}"`
2. Secret is mounted in `additionalExistingSecrets`
3. JCasC renders the value at startup

From `values.yaml`:
```yaml
additionalExistingSecrets:
  - name: jenkins-admin-password
    keyName: password
```

And in the security realm:
```yaml
password: "${jenkins-admin-password}"
```

## Troubleshooting

### Secret Not Found

If Jenkins fails to start with "secret not found" error:

```bash
# Check if secret exists
kubectl get secret jenkins-admin-password -n jenkins

# If missing, create it
bash scripts/manage-admin-password.sh create

# Restart Jenkins
kubectl rollout restart statefulset/jenkins-service -n jenkins
```

### Password Not Updating

If you change the password but Jenkins still uses the old one:

```bash
# Restart Jenkins after password change
helm upgrade -f values.yaml -n jenkins jenkins-service jenkins/jenkins

# Or directly restart the pod
kubectl rollout restart statefulset/jenkins-service -n jenkins
```

### Cannot Retrieve Password

If the script fails to retrieve the password:

```bash
# Check if secret exists and has data
kubectl describe secret jenkins-admin-password -n jenkins

# Manually decode
kubectl get secret jenkins-admin-password -n jenkins -o jsonpath='{.data.password}' | base64 -d
```

## Security Considerations

- **Kubernetes RBAC**: Ensure only authorized users can read the secret
  ```bash
  # Restrict secret access
  kubectl create rolebinding jenkins-secret-reader \
    --clusterrole=secret-reader \
    --serviceaccount=jenkins:jenkins-service \
    -n jenkins
  ```

- **Encrypted at Rest**: Use Kubernetes secret encryption if available
  ```bash
  # Check if encryption is enabled
  kubectl get secrets -n jenkins -o json | grep -i encrypt
  ```

- **Audit Logging**: Monitor secret access
  ```bash
  # View secret access events
  kubectl get events -n jenkins --field-selector involvedObject.kind=Secret
  ```

## Integration with CI/CD

To use the admin account in scripts:

```bash
# Get password for use in automation
PASSWORD=$(bash scripts/manage-admin-password.sh get | cut -d: -f2 | xargs)

# Use in API calls
curl -u admin:"$PASSWORD" https://localhost:8443/jenkins/api/json
```

## Cleanup on Uninstall

When running `./uninstall.sh`, the password secret is NOT automatically deleted (preserved for potential recovery). To delete it manually:

```bash
kubectl delete secret jenkins-admin-password -n jenkins
```

Or use the management script:

```bash
bash scripts/manage-admin-password.sh delete
```
