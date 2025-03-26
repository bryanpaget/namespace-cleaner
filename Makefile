.PHONY: test dry-run run stop clean

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
	@echo "Executing dry-run..."
	DRY_RUN=true TEST_MODE=false ./namespace-cleaner.sh

# Deploy to production
run:
	@echo "Deploying namespace cleaner..."
	kubectl apply -f configmap.yaml -f secret.yaml -f cronjob.yaml
	@echo "\nCronJob scheduled. Next run:"
	kubectl get cronjob namespace-cleaner -o jsonpath='{.status.nextScheduleTime}'

# Stop production deployment
stop:
	@echo "Stopping namespace cleaner..."
	kubectl delete -f cronjob.yaml --ignore-not-found
	@echo "Retaining configmap/secret for audit purposes."

# Clean test artifacts
clean-test:
	@echo "Cleaning test resources..."
	kubectl delete -f tests/test-config.yaml -f tests/test-cases.yaml --ignore-not-found
	rm -f ./cleaner-config.env

# Full cleanup (including production)
clean: clean-test
	@echo "Cleaning production resources..."
	kubectl delete -f configmap.yaml -f secret.yaml -f cronjob.yaml --ignore-not-found
