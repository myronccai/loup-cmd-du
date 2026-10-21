# Build, check and test commands for this host.native Loup application.
#
# On Linux x86-64 `loup` is the self-hosted driver and `loup-bootstrap` is
# Stage0. The binary is built by the self-hosted compiler
# (`loup build --target native`); `check` and the unit tests use Stage0,
# whose test runner builds every host.native test as a native binary. The
# sources therefore keep to what both native back ends compile alike.
# (`loup run` cannot call the libc functions the walk uses, so there is no
# interpreted lane.)

APP            ?= du
LOUP           ?= loup
LOUP_BOOTSTRAP ?= loup-bootstrap
BUILD_DIR      ?= build
BIN            := $(BUILD_DIR)/$(APP)
SOURCES        := package.lppkg $(shell find source -name '*.lphc')
ARGS           ?=
TEST_ARGS      ?=

.PHONY: all run check test build e2e ci clean

all: build

# Build the binary and run it, e.g. `make run ARGS="-h -d 1 /usr/share"`.
run: $(BIN)
	$(BIN) $(ARGS)

# Type-check source/main.lphc and every module it imports.
check:
	$(LOUP_BOOTSTRAP) check --no-color

# Each test_* function becomes its own native binary (about a second each).
# The generated test package lives in a temporary directory, so LOUPPATH
# must be absolute: source/ for the program's modules, tests/ for the
# shared helpers. Narrow the run with TEST_ARGS, e.g.
# `make test TEST_ARGS="--filter glob"`.
test:
	@mkdir -p .temp
	LOUPPATH=$(CURDIR)/source:$(CURDIR)/tests$${LOUPPATH:+:$$LOUPPATH} $(LOUP_BOOTSTRAP) test --native --no-color $(TEST_ARGS) > .temp/test.log 2>&1; \
	status=$$?; cat .temp/test.log; exit $$status
	@# A test file that does not compile is skipped silently ("found 0 tests"),
	@# so a full run must account for every test_ function.
	@if [ -z "$(TEST_ARGS)" ]; then \
	    want=$$(cat tests/*_test.lphc | grep -c '^func test_'); \
	    got=$$(sed -n 's/^Tests: \([0-9]*\) total.*/\1/p' .temp/test.log); \
	    if [ "$$want" != "$$got" ]; then \
	        echo "make test: ran $$got of $$want tests; a test file did not compile (find it with: LOUPPATH=source:tests loup-bootstrap run tests/FILE)"; \
	        exit 1; \
	    fi; \
	fi

# Native executable, built by the self-hosted compiler (needs clang).
build: $(BIN)

$(BIN): $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	$(LOUP) build --target native -o $@

# End-to-end tests: run the built binary on scratch trees in a temporary
# directory and compare its output and exit status with the expected ones.
e2e: $(BIN)
	bash tests/e2e.sh $(BIN)

# Everything CI runs, ending with a smoke test of the built binary.
ci: check test build e2e
	$(BIN) --version

clean:
	rm -rf $(BUILD_DIR) .temp .loup-cache
