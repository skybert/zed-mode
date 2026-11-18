EMACS ?= emacs
TESTS := $(wildcard *_test.el)

.PHONY: test coverage clean

test:
	$(EMACS) -Q --batch -L . $(addprefix -l ,$(TESTS)) -f ert-run-tests-batch-and-exit

# Run the tests with coverage, then fail if it is below .coverage-baseline.
coverage:
	$(EMACS) -Q --batch -L . -l zed_test_coverage.el -f zed-coverage-start \
	  $(addprefix -l ,$(TESTS)) -f ert-run-tests-batch-and-exit
	$(EMACS) -Q --batch -L . -l zed_test_coverage.el -f zed-coverage-check

clean:
	rm -rf .deps coverage.json *.elc
