# Nginx Reverse Proxy with TLS

This setup provides a secure HTTPS reverse proxy in front of Jenkins using self-signed certificates (suitable for localhost development).

## Overview

- **nginx** reverse proxy with TLS/HTTPS support
- **Self-signed certificates** for localhost domains
- **HTTP to HTTPS redirect** for automatic upgrade
- **WebSocket support** for Jenkins agent communication
- **Port forwarding** via NodePort (30080 HTTP, 30443 HTTPS)

## Quick Start

This nginx setup is **automatically deployed** when you run:

```bash
make install
```

The installation script will:
1. Generate self-signed TLS certificates
2. Deploy nginx reverse proxy
3. Configure Jenkins with `/jenkins` URI prefix
4. Start port-forwarding to nginx

## Management Commands

### Manual TLS Setup (if needed)
```bash
./scripts/manage-nginx.sh setup
```

### Manual Nginx Deployment
```bash
./scripts/manage-nginx.sh deploy
```

### Check Status
```bash
./scripts/manage-nginx.sh status
```

### Remove Nginx
```bash
./scripts/manage-nginx.sh remove
```

## Architecture

```
User Browser
    ↓
Nginx (HTTPS, port 443)
    ↓
Jenkins Service (HTTP, port 8080)
```

## Certificate Details

- **Type**: Self-signed X.509
- **Validity**: 365 days
- **CN**: localhost
- **SANs**: localhost, 127.0.0.1, jenkins
- **Key Type**: RSA 2048-bit
- **Storage**: Kubernetes TLS Secret (`nginx-tls`)

## Configuration Files

- **nginx-reverse-proxy.yaml**: Kubernetes resources (Deployment, Service, ConfigMap, Ingress)
- **setup-nginx-tls.sh**: TLS certificate generation script
- **manage-nginx.sh**: Helper script for setup/deploy/remove operations

## Troubleshooting

### Certificate Issues
If you get certificate errors, regenerate:
```bash
./scripts/manage-nginx.sh setup
kubectl rollout restart deployment/nginx-reverse-proxy -n jenkins
```

### Port Already in Use
If port 8443 is in use, forward to a different port:
```bash
kubectl port-forward -n jenkins svc/nginx-reverse-proxy 9443:443
```
Then access: **https://localhost:9443**

### Check Nginx Logs
```bash
kubectl logs -n jenkins -l app=nginx-reverse-proxy
```

### Verify Certificate
```bash
# Check certificate in the secret
kubectl get secret nginx-tls -n jenkins -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Adding Additional Backends (e.g., HashiCorp Vault)

The nginx configuration is designed to support multiple backend services. To add a new service like Vault:

### 1. Edit nginx-reverse-proxy.yaml

Uncomment and configure the upstream:

```yaml
upstream vault_backend {
  server vault:8200 max_fails=3 fail_timeout=30s;
}
```

Uncomment the location block:

```yaml
location /vault/ {
  proxy_pass http://vault_backend/;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_redirect off;
}
```

### 2. Deploy the updated configuration

```bash
kubectl apply -f scripts/nginx-reverse-proxy.yaml
kubectl rollout restart deployment/nginx-reverse-proxy -n jenkins
```

### 3. Access the service

- Jenkins: `https://localhost:8443/`
- Vault: `https://localhost:8443/vault/`

## Adding More Complex Backends

For services requiring specific proxy settings:

```yaml
location /myservice/ {
  proxy_pass http://myservice_backend/;
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_redirect ~^(.*) https://$host:$server_port$1;
  
  # WebSocket support (if needed)
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
}
```

## Health Check

The nginx proxy exposes a health endpoint at `/health` for monitoring:

```bash
curl https://localhost:8443/health --insecure
# Output: healthy
```
