.PHONY: test

# Run the policy test suite with the Kyverno CLI (https://kyverno.io/docs/kyverno-cli/)
test:
	kyverno test tests
