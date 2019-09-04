SHELL:=/bin/bash
ARCH:=$(shell uname -m)

# Sysboxd source-code locations.
SYSBOXD_DIR  := $(CURDIR)/../..
SYSBOX_FS    := $(SYSBOXD_DIR)/sysbox-fs
SYSBOX_IPC   := $(SYSBOXD_DIR)/sysbox-ipc
SYSBOX_MGR   := $(SYSBOXD_DIR)/sysbox-mgr
SYSBOX_RUNC  := $(SYSBOXD_DIR)/sysbox-runc
SYSBOXD_SOURCE_CODE := SYSBOX_FS SYSBOX_IPC SYSBOX_MGR SYSBOX_RUNC

# Sysboxd build-instructions locations.
SYSBOXD_IMAGE_COMMON := common
SYSBOXD_IMAGE_SYSTEMD := ../systemd
SYSBOXD_IMAGE_SOURCES := SYSBOXD_IMAGE_COMMON SYSBOXD_IMAGE_SYSTEMD

SOURCE_FILES =  sysboxd.tgz          \
		sysboxd.service      \
		sysbox-fs.service    \
		sysbox-mgr.service   \
		sysboxd-systemd.conf

SOURCES=$(addprefix sources/, $(SOURCE_FILES))

# Go version to utilize in slave containers for the building process.
# We are temporarily skipping these settings as we are relying on Go's
# top-of-tree (till 1.13 comes out).
GO_BASE_IMAGE=golang
GO_VERSION:=1.13
GO_IMAGE=$(GO_BASE_IMAGE):$(GO_VERSION)

CHOWN:=docker run --rm -v $(CURDIR):/v -w /v alpine chown

DOCKER_BUILD=docker build                              \
	--build-arg GO_IMAGE=$(GO_IMAGE)                   \
	--build-arg COMMON_FILES=$(SYSBOXD_IMAGE_COMMON)  \
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


sources/sysboxd.tgz:
	mkdir -p $(@D)
	docker run --rm -i -w /v                                         \
		-v $(SYSBOXD_DIR):/sysboxd                               \
		-v $(CURDIR)/$(@D):/v                                    \
		alpine                                                   \
		tar -C / -czf /v/sysboxd.tgz --exclude='images' sysboxd

sources/sysboxd.service: ../systemd/sysboxd.service
	mkdir -p $(@D)
	cp $< $@

sources/sysbox-fs.service: ../systemd/sysbox-fs.service
	mkdir -p $(@D)
	cp $< $@

sources/sysbox-mgr.service: ../systemd/sysbox-mgr.service
	mkdir -p $(@D)
	cp $< $@

sources/sysboxd-systemd.conf: ../systemd/sysboxd-systemd.conf
	mkdir -p $(@D)
	cp $< $@
