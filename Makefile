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

TESTS = test-fmt test-generated test-valid test-prom_rules-v1 test-prom_rules-v2

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

# Docker prometheus IMAGE by major prometheus release
test-prom_rules-v1: IMAGE = prom/prometheus:v1.8.2
test-prom_rules-v2: IMAGE = prom/prometheus:v2.0.0
migrate-prom_rules-v2: IMAGE = prom/prometheus:v2.0.0

# Test both prometheus.yml and rules files - as generated files
# are json, prometheus.yml needs to be extracted from each prometheus_config.json,
# which is done with 'to-yml' below (and cleaned up by 'rm-yml')
test-prom_rules-%: tests/test_prom_rules.sh
	$(DOCKER_RUN) kube-manifests $< to-yml
	$(DOCKER_RUN) -v $(CURDIR)/common/config:/etc/prometheus-config --entrypoint /bin/sh $(IMAGE) $< $(*)
	$(DOCKER_RUN) kube-manifests $< rm-yml

migrate-prom_rules-v2: tools/prometheus2_migrate_rules.sh
	$(DOCKER_RUN) --entrypoint /bin/sh $(IMAGE) $<

test: $(TESTS)

.PHONY: all build test docker-kube-manifests
