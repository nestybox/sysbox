#
# Sysbox-in-docker Makefile.
#
# The targets in this Makefile offer a simple approach to build a docker-image
# to run a containerized Sysbox environment.
#


SHELL:=/bin/bash
SIND_IMAGE := nestybox/sysbox-in-docker


.DEFAULT := help

.PHONY: help            \
	centos-8        \
	debian-buster   \
	debian-bullseye \
	fedora-31       \
	fedora-32       \
	ubuntu-bionic   \
	ubuntu-focal


.DEFAULT := help

help: ## Show supported docker images
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  \
	make sysbox-in-docker \033[36m<distro-release>\033[0m\n\n"} \
	/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


LAUNCH_INSTRUCTION := docker run -it --privileged --rm --hostname sysbox-in-docker --name sysbox-in-docker \
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

ubuntu-focal: ## Build Ubuntu-Focal docker image
	@printf "\n** Building $@ sysbox-in-docker image **\n\n"
	@docker build -t $(SIND_IMAGE):$@ -f Dockerfile.$@ .
	@printf "\n*** Launch container with the following instruction ***\n\n"
	@printf "$(LAUNCH_INSTRUCTION) "
	@printf "$(SIND_IMAGE):$@\n\n"
