.PHONY: help install upgrade start-tunnel uninstall password-get password-set password-create redeploy logs

# Default target shows the help menu
help:
	@echo "-----------------------------------------------------------------------"
	@echo "Jenkins Kubernetes Management CLI"
	@echo "-----------------------------------------------------------------------"
	@echo "Usage: make [target]"
	@echo ""
	@echo "Installation & Lifecycle:"
	@echo "  install       - Check namespace and perform fresh Jenkins installation"
	@echo "  upgrade       - Apply values.yaml changes and restart Jenkins service"
	@echo "  uninstall     - Full cleanup: remove release, namespace, and tunnels"
	@echo ""
	@echo "Admin Password Management:"
	@echo "  password-get  - Retrieve current Jenkins admin password"
	@echo "  password-set  - Change Jenkins admin password (prompts for new password)"
	@echo "  password-create - Create new admin password secret (if missing)"
	@echo ""
	@echo "Deployment & Debugging:"
	@echo "  redeploy      - Full restart of Jenkins (useful after config changes)"
	@echo "  start-tunnel  - Establish port-forward tunnel (https://localhost:8443)"
	@echo "  logs          - Show Jenkins pod logs"
	@echo ""
	@echo "help          - Show this help menu"
	@echo "-----------------------------------------------------------------------"

install:
	@chmod +x scripts/install.sh
	@./scripts/install.sh

upgrade:
	@chmod +x scripts/upgrade.sh
	@./scripts/upgrade.sh

start-tunnel:
	@chmod +x scripts/start-tunnel.sh
	@./scripts/start-tunnel.sh

uninstall:
	@chmod +x scripts/uninstall.sh
	@./scripts/uninstall.sh

password-get:
	@bash scripts/manage-admin-password.sh get

password-set:
	@bash scripts/manage-admin-password.sh update

password-create:
	@bash scripts/manage-admin-password.sh create

redeploy:
	@echo "[INFO] Redeploying Jenkins..."
	@helm upgrade -f values.yaml -n jenkins jenkins-service jenkins/jenkins || true
	@echo "[INFO] Waiting for Jenkins to roll out..."
	@kubectl rollout status -n jenkins statefulset/jenkins-service --timeout=300s || true
	@echo "[INFO] ✅ Redeploy complete. Jenkins is restarting."
	@echo "[INFO] Access at: https://localhost:8443/jenkins"

logs:
	@kubectl logs -f -n jenkins -l app.kubernetes.io/instance=jenkins-service -c jenkins