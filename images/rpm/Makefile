SHELL:=/bin/bash
ARCH:=$(shell uname -m)

# Sysvisor source-code locations.
SYSVISOR_DIR  := $(CURDIR)/../..
SYSVISOR_FS   := $(SYSVISOR_DIR)/sysvisor-fs
SYSVISOR_IPC  := $(SYSVISOR_DIR)/sysvisor-ipc
SYSVISOR_MGR  := $(SYSVISOR_DIR)/sysvisor-mgr
SYSVISOR_RUNC := $(SYSVISOR_DIR)/sysvisor-runc
SYSVISOR_SOURCE_CODE := SYSVISOR_FS SYSVISOR_IPC SYSVISOR_MGR SYSVISOR_RUNC

# Sysvisor build-instructions locations.
SYSVISOR_IMAGE_COMMON := common
SYSVISOR_IMAGE_SYSTEMD := ../systemd
SYSVISOR_IMAGE_SOURCES := SYSVISOR_IMAGE_COMMON SYSVISOR_IMAGE_SYSTEMD

SOURCE_FILES =  sysvisor.tgz           \
		sysvisor.service       \
		sysvisor-fs.service    \
		sysvisor-mgr.service   \
		sysvisor-systemd.conf

SOURCES=$(addprefix sources/, $(SOURCE_FILES))

# Go version to utilize in slave containers for the building process.
# We are temporarily skipping these settings as we are relying on Go's
# top-of-tree (till 1.13 comes out).
GO_BASE_IMAGE=golang
GO_VERSION:=1.12.5
GO_IMAGE=$(GO_BASE_IMAGE):$(GO_VERSION)

CHOWN:=docker run --rm -v $(CURDIR):/v -w /v alpine chown

DOCKER_BUILD=docker build                                  \
	--build-arg GO_IMAGE=$(GO_IMAGE)                   \
	--build-arg COMMON_FILES=$(SYSVISOR_IMAGE_COMMON)  \
	-t rpmbuild-$@/$(ARCH)                             \
	-f $(CURDIR)/$@/Dockerfile .

DOCKER_RUN=docker run --rm -i                    \
	-e PLATFORM                              \
	-v $(CURDIR)/rpmbuild/$@:/build          \
	-v $(GOPATH)/pkg/mod:/go/pkg/mod         \
	rpmbuild-$@/$(ARCH)


.PHONY: help     \
	rpm          \
	centos       \
	centos-7     \
	fedora       \
	fedora-30    \
	fedora-29    \
	fedora-28    \
	clean

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  \
	make image build-rpm \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-0-9]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ RPM building targets

rpm: centos fedora

centos: ## Build all Centos rpm packages
centos: centos-7

centos-7: ## Build Centos-7 packages
centos-7: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) rpmbuild/$@

fedora: ## Build all Fedora rpm packages
fedora: fedora-30 fedora-29 fedora-28

fedora-30: ## Build Fedora-30 packages
fedora-30: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) rpmbuild/$@

fedora-29: ## Build Fedora-29 packages
fedora-29: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) rpmbuild/$@

fedora-28: ## Build Fedora-28 packages
fedora-28: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) rpmbuild/$@

clean: ## Remove build artifacts
	[ ! -d rpmbuild ] || $(CHOWN) -R $(shell id -u):$(shell id -g) rpmbuild
	$(RM) -r rpmbuild
	[ ! -d sources ] || $(CHOWN) -R $(shell id -u):$(shell id -g) sources
	$(RM) -r sources

sources/sysvisor.tgz:
	mkdir -p $(@D)
	docker run --rm -i -w /v \
		-v $(SYSVISOR_DIR):/sysvisor \
		-v $(CURDIR)/$(@D):/v \
		alpine \
		tar -C / -czf /v/sysvisor.tgz --exclude .git --exclude='images' sysvisor

sources/sysvisor.service: ../systemd/sysvisor.service
	mkdir -p $(@D)
	cp $< $@

sources/sysvisor-fs.service: ../systemd/sysvisor-fs.service
	mkdir -p $(@D)
	cp $< $@

sources/sysvisor-mgr.service: ../systemd/sysvisor-mgr.service
	mkdir -p $(@D)
	cp $< $@

sources/sysvisor-systemd.conf: ../systemd/sysvisor-systemd.conf
	mkdir -p $(@D)
	cp $< $@
