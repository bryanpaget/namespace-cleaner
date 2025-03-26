# Final Makefile
.PHONY: apply-config clean test

test: apply-config run verify

apply-config:
	@echo "Applying test configurations..."
	kubectl apply -f tests/test-config.yaml
	kubectl apply -f tests/test-cases.yaml

run:
	@echo "\nRunning namespace cleaner..."
	TEST_MODE=true ./namespace-cleaner.sh

verify:
	@echo "\nVerification:"
	@kubectl get ns -l app.kubernetes.io/part-of=kubeflow-profile

clean:
	@echo "Cleaning up..."
	kubectl delete -f tests/test-config.yaml
	kubectl delete ns test-valid-user test-invalid-user test-expired-ns
	rm ./cleaner-config.env
