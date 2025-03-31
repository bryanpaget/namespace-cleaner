.PHONY: test dry-run install upgrade uninstall clean-test clean

HELM_RELEASE = namespace-cleaner
HELM_CHART_PATH = helm/namespace-cleaner

# Local testing (no Azure, real execution)
test:
	@echo "Running local test suite..."
	kubectl apply -f tests/test-config.yaml -f tests/test-cases.yaml
	DRY_RUN=false TEST_MODE=true ./namespace-cleaner.sh
	@echo "\nVerification:"
	@kubectl get ns -l app.kubernetes.io/part-of=kubeflow-profile
	@make clean-test

# Dry-run mode (no changes)
dry-run:
	@echo "Executing production dry-run (real Azure checks)"
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART_PATH) --set dryRun=true
	@echo "Dry-run complete. Check logs for details."

# Install to production
install:
	@echo "Installing namespace cleaner via Helm..."
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART_PATH)
	@echo "\nCronJob scheduled. Next run:"
	kubectl get cronjob namespace-cleaner -o jsonpath='{.status.nextScheduleTime}'

# Upgrade deployment
upgrade:
	@echo "Upgrading namespace cleaner..."
	helm upgrade $(HELM_RELEASE) $(HELM_CHART_PATH)
	@echo "Upgrade complete."

# Uninstall deployment
uninstall:
	@echo "Uninstalling namespace cleaner..."
	helm uninstall $(HELM_RELEASE)
	@echo "Cleanup complete."

# Clean test artifacts
clean-test:
	@echo "Cleaning test resources..."
	kubectl delete -f tests/test-config.yaml -f tests/test-cases.yaml --ignore-not-found

# Full cleanup (including production)
clean: clean-test uninstall
	@echo "All namespace-cleaner resources removed."
