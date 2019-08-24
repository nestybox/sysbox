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

DOCKER_BUILD=docker build                              \
	--build-arg GO_IMAGE=$(GO_IMAGE)                   \
	--build-arg COMMON_FILES=$(SYSVISOR_IMAGE_COMMON)  \
	-t debbuild-$@/$(ARCH)                             \
	-f $(CURDIR)/$@/Dockerfile .

DOCKER_RUN=docker run --rm -i                \
	-e PLATFORM                              \
	-e VERSION                               \
	-e COMMIT_ID                             \
	-e BUILT_BY                              \
	-e HOSTNAME                              \
	-v $(CURDIR)/debbuild/$@:/build          \
	-v $(GOPATH)/pkg/mod:/go/pkg/mod         \
	debbuild-$@/$(ARCH)


.PHONY: help       \
	deb            \
	debian         \
	debian-buster  \
	debian-stretch \
	ubuntu         \
	ubuntu-disco   \
	ubuntu-cosmic  \
	ubuntu-bionic  \
	clean

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  \
	make image build-deb \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ DEB building targets

deb: debian ubuntu

debian: ## Build all Debian deb packages
debian: debian-stretch debian-buster

debian-buster: ## Build Debian Buster (10) packages
debian-buster: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) debbuild/$@

debian-stretch: ## Build Debian Buster (9) packages
debian-stretch: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) debbuild/$@

ubuntu: ## Build all Ubuntu deb packages
ubuntu: ubuntu-bionic ubuntu-cosmic ubuntu-disco

ubuntu-disco: ## Build Ubuntu Disco (19.04) deb packages
ubuntu-disco: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) debbuild/$@

ubuntu-cosmic: ## Build Ubuntu Cosmic (18.10) deb packages
ubuntu-cosmic: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) debbuild/$@

ubuntu-bionic: ## Build Ubuntu Bionic (18.04) deb packages
ubuntu-bionic: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) debbuild/$@


clean: ## Remove build artifacts
	[ ! -d debbuild ] || $(CHOWN) -R $(shell id -u):$(shell id -g) debbuild
	$(RM) -r debbuild
	[ ! -d sources ] || $(CHOWN) -R $(shell id -u):$(shell id -g) sources
	$(RM) -r sources


sources/sysvisor.tgz:
	mkdir -p $(@D)
	docker run --rm -i -w /v \
		-v $(SYSVISOR_DIR):/sysvisor \
		-v $(CURDIR)/$(@D):/v \
		alpine \
		tar -C / -czf /v/sysvisor.tgz --exclude='images' sysvisor

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
