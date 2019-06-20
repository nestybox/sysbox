SHELL:=/bin/bash
ARCH=$(shell uname -m)

.PHONY: help      \
		build     \
		build-deb \
		build-rpm \
		clean     \
		clean-deb \
		clean-rpm

help: ## Show build targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf " \033[36m%-20s\033[0m  %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build debian and rpm packages
build: build-deb build-rpm

build-deb: SYSVISOR_BUILD_PKGS:=$(shell find deb -maxdepth 1 -type d | egrep "debian.*|ubuntu.*" | sed 's/^deb\///')
build-deb: ## Build debian packages
	for p in $(SYSVISOR_BUILD_PKGS); do \
		$(MAKE) -C deb $${p}; \
	done

# Note: Sysvisor rpm images are not supported yet.
build-rpm: SYSVISOR_BUILD_PKGS:=$(shell find rpm -maxdepth 1 -type d | egrep "fedora.*|centos.*" | sed 's/^deb\///')
build-rpm: ## Build rpm packages
	for p in $(SYSVISOR_BUILD_PKGS); do \
		$(MAKE) -C rpm $${p}; \
	done

clean: ## Remove build artifacts
	$(MAKE) -C deb clean
	# $(MAKE) -C rpm clean

clean-deb: ## Remove deb build artifacts
	$(MAKE) -C deb clean

clean-rpm: ## Remove rpm build artifacts
	# $(MAKE) -C rpm clean
