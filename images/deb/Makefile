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

# ifdef BUILD_IMAGE
# 	BUILD_IMAGE_FLAG=--build-arg $(BUILD_IMAGE)
# endif

CHOWN:=docker run --rm -v $(CURDIR):/v -w /v alpine chown

DOCKER_BUILD=docker build                                  \
	--build-arg GO_IMAGE=$(GO_IMAGE)                   \
	--build-arg COMMON_FILES=$(SYSVISOR_IMAGE_COMMON)  \
	-t debbuild-$@/$(ARCH)                             \
	-f $(CURDIR)/$@/Dockerfile .

DOCKER_RUN=docker run --rm -i                    \
	-e PLATFORM                              \
	-v $(CURDIR)/debbuild/$@:/build          \
	-v $(GOPATH)/pkg/mod:/go/pkg/mod         \
	debbuild-$@/$(ARCH)


.PHONY: help     \
	deb      \
	debian   \
	debian-% \
	ubuntu   \
	ubuntu-% \
	clean

help: ## Show build targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf " \033[36m%-20s\033[0m  %s\n", $$1, $$2}' $(MAKEFILE_LIST)

clean: ## Remove build artifacts
	[ ! -d debbuild ] || $(CHOWN) -R $(shell id -u):$(shell id -g) debbuild
	$(RM) -r debbuild
	[ ! -d sources ] || $(CHOWN) -R $(shell id -u):$(shell id -g) sources
	$(RM) -r sources

 ## Build all deb packages
deb: debian ubuntu

 ## Build all Debian deb packages
debian: debian-stretch debian-buster

ubuntu: ## Build all Ubuntu deb packages
ubuntu: ubuntu-bionic ubuntu-cosmic ubuntu-disco

debian-%: ## Build Debian deb packages
debian-%: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) debbuild/$@

ubuntu-%: ## Build Ubuntu deb packages
ubuntu-%: $(SOURCES)
	$(DOCKER_BUILD)
	$(DOCKER_RUN)
	$(CHOWN) -R $(shell id -u):$(shell id -g) debbuild/$@

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
