# Provides 'build' and 'test' targets.  Uses docker.

UID := $(shell id -u)
GID := $(shell id -g)

# Eg: if you need sudo, run with DOCKER_PREFIX=sudo
DOCKER_PREFIX =

DOCKER = $(DOCKER_PREFIX) docker
DOCKER_BUILD = $(DOCKER) build --build-arg http_proxy=$(http_proxy)
DOCKER_RUN = $(DOCKER) run --rm --network=host -u $(UID):$(GID) \
 -v $(CURDIR):$(CURDIR) -w $(CURDIR) \
 -v $(HOME)/.kube/config:/kubeconfig \
 -v $(HOME)/.kube/cache:/home/user/.kube/cache \
 -e TERM=$(TERM) -e KUBECONFIG=/kubeconfig

TESTS = test-fmt test-generated test-valid test-prom_rules

all: build

docker-kube-manifests: tests/Dockerfile
# --build-arg breaks docker caching, so fake it ourselves
	if [ -z "$(shell $(DOCKER) images -q kube-manifests)" ]; then \
	  $(DOCKER_BUILD) -t kube-manifests tests; \
	fi

build: docker-kube-manifests
	$(DOCKER_RUN) kube-manifests tools/rebuild.sh

test-%: tests/test_%.sh docker-kube-manifests
	$(DOCKER_RUN) kube-manifests $<

test-prom_rules: tests/test_prom_rules.sh
	$(DOCKER_RUN) --entrypoint /bin/sh prom/prometheus $<

test: $(TESTS)

.PHONY: all build test docker-kube-manifests
