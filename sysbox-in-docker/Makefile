#
# Sysbox-in-docker Makefile.
#
# The targets in this Makefile offer a simple approach to build a docker-image
# to run a containerized Sysbox environment.
#

SHELL:=/bin/bash
SIND_IMAGE := nestybox/sysbox-in-docker

.PHONY: help            \
	centos-8        \
	debian-buster   \
	debian-bullseye \
	fedora-31       \
	fedora-32       \
	ubuntu-bionic   \
	ubuntu-focal

# Host kernel info
KERNEL_REL := $(shell uname -r)
export KERNEL_REL

# Sysbox image-generation globals utilized during the sysbox's building and testing process.
IMAGE_BASE_DISTRO := $(shell lsb_release -is | tr '[:upper:]' '[:lower:]')
ifeq ($(IMAGE_BASE_DISTRO),$(filter $(IMAGE_BASE_DISTRO),centos fedora redhat))
	IMAGE_BASE_RELEASE := $(shell lsb_release -ds | tr -dc '0-9.' | cut -d'.' -f1)
	KERNEL_HEADERS := kernels/$(KERNEL_REL)
	KERNEL_HEADERS_MOUNTS := -v /usr/src/$(KERNEL_HEADERS):/usr/src/$(KERNEL_HEADERS):ro
else
	IMAGE_BASE_RELEASE := $(shell lsb_release -cs)
	KERNEL_HEADERS := linux-headers-$(KERNEL_REL)
	KERNEL_HEADERS_BASE := $(shell find /usr/src/$(KERNEL_HEADERS) -maxdepth 1 -type l -exec readlink {} \; | cut -d"/" -f2 | egrep -v "^\.\." | head -1)
	KERNEL_HEADERS_MOUNTS := -v /usr/src/$(KERNEL_HEADERS):/usr/src/$(KERNEL_HEADERS):ro \
				 -v /usr/src/$(KERNEL_HEADERS_BASE):/usr/src/$(KERNEL_HEADERS_BASE):ro
endif

.DEFAULT := help

help: ## Show supported docker images
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  \
	make \033[36m<distro-release>\033[0m\n\n"} \
	/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


LAUNCH_INSTRUCTION := docker run -d --privileged --rm --hostname sysbox-in-docker --name sysbox-in-docker \
                -v /var/tmp/sysbox-var-lib-docker:/var/lib/docker \
                -v /var/tmp/sysbox-var-lib-sysbox:/var/lib/sysbox \
                -v /lib/modules/$$(uname -r):/lib/modules/$$(uname -r):ro \
		$(KERNEL_HEADERS_MOUNTS)


centos-8: ## Build CentOS-8 docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@echo $(LAUNCH_INSTRUCTION)
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"

debian-buster: ## Build Debian-Buster docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"

debian-bullseye: ## Build Debian-Bullseye docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"

fedora-31: ## Build Fedora-31 docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"

fedora-32: ## Build Fedora-32 docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"

ubuntu-bionic: ## Build Ubuntu-Bionic docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"

ubuntu-eoan: ## Build Ubuntu-Eoan docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"

ubuntu-focal: ## Build Ubuntu-Focal docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"
