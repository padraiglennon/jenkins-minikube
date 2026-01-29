# Jenkins Configuration as Code (JCasC)

This folder documents the Jenkins Configuration as Code setup for this deployment.

## Overview

JCasC allows you to define Jenkins configuration in YAML format instead of manually configuring through the UI. All JCasC configuration is managed through the `values.yaml` file's `controller.JCasC` section.

## Configuration Structure

The JCasC configuration is defined in [../values.yaml](../values.yaml) under `controller.JCasC.configScripts`:

### Current Configurations

#### 1. Welcome Message (`welcome-message`)
- Sets a system message displayed on Jenkins dashboard
- Basic example of JCasC configuration

#### 2. Smoke Tests Folder (`smoke-tests`)
- Creates a Jenkins folder named "smoke-tests"
- Initializes the folder structure for smoke test pipelines
- Works in conjunction with the init scripts in `../scripts/`

## How JCasC Works

1. **Configuration Scripts**: Each key under `configScripts` becomes a YAML file in `/var/jenkins_home/casc_configs/`
2. **Auto-reload Sidecar**: The `configAutoReload` sidecar monitors these files for changes
3. **On-demand Reload**: Changes trigger automatic reload via HTTP endpoint when `enabled: true`
4. **Initialization**: Configuration is applied during Jenkins startup

## Modifying Configuration

To add or modify JCasC configuration:

1. Edit the `controller.JCasC.configScripts` section in [../values.yaml](../values.yaml)
2. Add a new key-value pair or modify existing ones
3. Run `make upgrade` to deploy the changes
4. Jenkins will automatically reload the configuration

## Available JCasC Attributes

For a complete reference of available JCasC configuration options, see:
- Official documentation: https://github.com/jenkinsci/configuration-as-code-plugin
- Jenkins instance reference: `http://your-jenkins-url/configuration-as-code/reference`

## Example: Adding New Configuration

```yaml
JCasC:
  configScripts:
    welcome-message: |
      jenkins:
        systemMessage: Welcome to Jenkins
    
    my-new-config: |
      jenkins:
        # Your configuration here
        numExecutors: 2
        mode: NORMAL
```

## Folder and Job Creation

The `smoke-tests` folder creation is handled in two parts:

1. **JCasC** (values.yaml): Creates the folder structure
2. **Init Script** (scripts/smoke-tests-init-scripts.yaml): Populates the folder with jobs

This separation keeps values.yaml lightweight while allowing dynamic job creation via Groovy init scripts.

## Security Considerations

- Configuration files are stored in the Jenkins home directory
- Sensitive data should use Jenkins Credentials plugin
- The `configAutoReload` sidecar runs with restricted security context
- File permissions are handled by Kubernetes RBAC and Pod Security Standards

## Troubleshooting

### Configuration Not Applied
- Check Jenkins logs for JCasC errors
- Verify YAML syntax in values.yaml
- Ensure ConfigMap is mounted correctly in the pod

### Auto-reload Not Working
- Verify `configAutoReload.enabled: true` in values.yaml
- Check sidecar logs: `kubectl logs -f <jenkins-pod> -c config-reloader`
- Verify folder permissions at `/var/jenkins_home/casc_configs`
