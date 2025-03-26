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
	@echo "Checking valid namespace exists..."
	@kubectl get ns test-valid-user || (echo "::error::Valid namespace missing" && exit 1)
	@echo "Checking invalid namespace deleted..."
	@! kubectl get ns test-invalid-user 2>/dev/null || (echo "::error::Invalid namespace exists" && exit 1)
	@echo "Checking expired namespace deleted..."
	@! kubectl get ns test-expired-ns 2>/dev/null || (echo "::error::Expired namespace exists" && exit 1)
	@echo "All tests passed!"

clean:
	@echo "Cleaning up..."
	kubectl delete -f tests/test-config.yaml
	kubectl delete ns test-valid-user test-invalid-user test-expired-ns
	rm ./cleaner-config.env
