#
# Sysbox Makefile
#
# TODO:
# - Add installation package target
# - Eliminate image-build targets (e.g. ubuntu-bionic) from here. This is a hack to
#   workaround an unsolved issue, but it hurts on my eyes.

.PHONY: sysbox sysbox-static \
	sysbox-runc sysbox-runc-static sysbox-runc-debug \
	sysbox-fs sysbox-fs-static sysbox-fs-debug \
	sysbox-mgr sysbox-mgr-static sysbox-mgr-debug \
	sysbox-ipc \
	install uninstall \
	test \
	test-sysbox test-sysbox-shiftuid test-sysbox-local \
	test-runc test-fs test-mgr \
	test-shell test-shell-shiftuid \
	test-fs-local test-mgr-local \
	test-shiftfs test-shiftfs-local \
	test-img test-cleanup \
	image \
	listRuncPkgs listFsPkgs listMgrPkgs \
	pjdfstest pjdfstest-clean \
	build-deb ubuntu-bionic ubuntu-cosmic ubuntu-disco \
	test-installer \
	test-sysbox-installer test-sysbox-shiftuid-installer \
	test-shell-installer test-shell-shiftuid-installer \
	test-cntr-installer test-img-installer \
	clean

export SHELL=bash

# Global env-vars to carry metadata associated to image-builds. This state will
# be consumed by the sysbox submodules and exposed through the --version cli option.
#export VERSION=${shell cat ./VERSION}
export VERSION := $(shell egrep -m 1 "\[|\]" CHANGELOG.md | cut -d"[" -f2 | cut -d"]" -f1)
export BUILT_AT=${shell date}
# We don't want previously-set env-vars to be reset should this makefile is
# ever visited again in the same building cycle (i.e. docker image builders).
ifeq ($(COMMIT_ID),)
export COMMIT_ID=$(shell git rev-parse --short HEAD)
endif
ifeq ($(BUILT_BY),)
export BUILT_BY=${USER}
endif
ifeq ($(HOSTNAME),)
export HOSTNAME=$(shell hostname)
endif

# Source-code paths of the sysbox binary targets.
SYSRUNC_DIR     := sysbox-runc
SYSFS_DIR       := sysbox-fs
SYSMGR_DIR      := sysbox-mgr
SYSIPC_DIR      := sysbox-ipc
LIB_SECCOMP_DIR := lib/seccomp-golang
SHIFTFS_DIR     := shiftfs

# Consider to have this one moved out within sysbox-runc folder.
SYSRUNC_BUILDTAGS := seccomp apparmor

PROJECT := /root/nestybox/sysbox

# Sysbox binary targets destination.
ifeq ($(DESTDIR),)
INSTALL_DIR := /usr/local/sbin
else
INSTALL_DIR := ${DESTDIR}
endif

TEST_DIR := $(CURDIR)/tests
TEST_IMAGE := sysbox-test
TEST_INSTALLER_IMAGE := sysbox-installer-test
TEST_INSTALLER_DOCKERFILE := Dockerfile.installer

# Host kernel info
KERNEL_REL := $(shell uname -r)

# Sysbox image-generation globals utilized during the testing of sysbox installer.
IMAGE_BASE_DISTRO := $(shell lsb_release -ds | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')
IMAGE_BASE_RELEASE := $(shell lsb_release -cs)
IMAGE_FILE_PATH := image/deb/debbuild/$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE)
IMAGE_FILE_NAME := sysbox_$(VERSION)-0.$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE)_amd64.deb

# Volumes to mount into the privileged test container. These are
# required because certain mounts inside the test container can't
# be backed by overlayfs (e.g., /var/lib/docker, /var/lib/sysbox, etc.).
# Note that the volumes must not be on tmpfs either, because the
# docker engine inside the privileged test container will mount overlayfs
# on top , and overlayfs can't be mounted on top of tmpfs.
TEST_VOL1 := /var/tmp/sysbox-test-var-lib-docker
TEST_VOL2 := /var/tmp/sysbox-test-var-lib-sysbox
TEST_VOL3 := /var/tmp/sysbox-test-scratch

#
# build targets
# TODO: parallelize building of runc, fs, and mgr; note that grpc must be built before these.
#

.DEFAULT := help

help:
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ \
	{ printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Building targets

#
# libseccomp (used by Sysbox components)
#

LIBSECCOMP := lib/seccomp/src/.libs/libseccomp.a
LIBSECCOMP_DIR := lib/seccomp
LIBSECCOMP_SRC := $(shell find $(LIBSECCOMP_DIR)/src 2>&1 | grep -E '.*\.(c|h)')
LIBSECCOMP_SRC += $(shell find $(LIBSECCOMP_DIR)/include 2>&1 | grep -E '.*\.h')
$(LIBSECCOMP): $(LIBSECCOMP_SRC)
	@echo "Building libseccomp ..."
	@cd $(LIBSECCOMP_DIR) && ./autogen.sh && ./configure && make
	@echo "Building libseccomp completed."

#
# sysbox
#

sysbox: ## Build all sysbox modules
sysbox: sysbox-runc sysbox-fs sysbox-mgr
	@echo $(HOSTNAME) > .buildinfo

sysbox-debug: ## Build all sysbox modules (compiler optimizations off)
sysbox-debug: sysbox-runc-debug sysbox-fs-debug sysbox-mgr-debug

sysbox-static: ## Build all sysbox modules (static linking)
sysbox-static: sysbox-runc-static sysbox-fs-static sysbox-mgr-static

sysbox-runc: ## Build sysbox-runc module
sysbox-runc: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)"

sysbox-runc-debug: ## Build sysbox-runc module (compiler optimizations off)
sysbox-runc-debug: sysbox-ipc
	@cd $(SYSRUNC_DIR) && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" sysbox-runc-debug

sysbox-runc-static: ## Build sysbox-runc module (static linking)
sysbox-runc-static: sysbox-ipc
	@cd $(SYSRUNC_DIR) && make static

sysbox-fs: ## Build sysbox-fs module
sysbox-fs: $(LIBSECCOMP) sysbox-ipc
	@cd $(SYSFS_DIR) && make

sysbox-fs-debug: ## Build sysbox-fs module (compiler optimizations off)
sysbox-fs-debug: sysbox-ipc
	@cd $(SYSFS_DIR) && make sysbox-fs-debug

sysbox-fs-static: ## Build sysbox-fs module (static linking)
sysbox-fs-static: sysbox-ipc
	@cd $(SYSFS_DIR) && make sysbox-fs-static

sysbox-mgr: ## Build sysbox-mgr module
sysbox-mgr: sysbox-ipc
	@cd $(SYSMGR_DIR) && make

sysbox-mgr-debug: ## Build sysbox-mgr module (compiler optimizations off)
sysbox-mgr-debug: sysbox-ipc
	@cd $(SYSMGR_DIR) && make sysbox-mgr-debug

sysbox-mgr-static: ## Build sysbox-mgr module (static linking)
sysbox-mgr-static: sysbox-ipc
	@cd $(SYSMGR_DIR) && make sysbox-mgr-static

sysbox-ipc:
	@cd $(SYSIPC_DIR) && make sysbox-ipc


#
# install targets (require root privileges)
#

##@ Installation targets

install: ## Install all sysbox binaries
	install -D -m0755 sysbox-fs/sysbox-fs $(INSTALL_DIR)/sysbox-fs
	install -D -m0755 sysbox-mgr/sysbox-mgr $(INSTALL_DIR)/sysbox-mgr
	install -D -m0755 sysbox-runc/sysbox-runc $(INSTALL_DIR)/sysbox-runc
	install -D -m0755 bin/sysbox $(INSTALL_DIR)/sysbox

uninstall: ## Uninstall all sysbox binaries
	rm -f $(INSTALL_DIR)/sysbox
	rm -f $(INSTALL_DIR)/sysbox-fs
	rm -f $(INSTALL_DIR)/sysbox-mgr
	rm -f $(INSTALL_DIR)/sysbox-runc

#
# Test targets
#
# These targets run Sysbox tests within a privileged test container.
# they are meant as development tests.
#
# We also have targets that run tests within a privileged test
# container with Systemd + the Sysbox package installed. See "Test
# Sysbox Installer targets" below.
#

HEADERS := linux-headers-$(KERNEL_REL)

# hacky: works on ubuntu but may not work on other distros
HEADERS_BASE := $(shell find /usr/src/$(HEADERS) -maxdepth 1 -type l -exec readlink {} \; | cut -d"/" -f2 | head -1)

# Alternative: reads symlinks and finds longest common prefix with sed (works on shell but fails on makefile for some reason)
# HEADERS_BASE := $(shell find /usr/src/$(HEADERS) -maxdepth 1 -type l -exec readlink -f {} \; | uniq | sed -e 's,$,/,;1{h;d;}' -e 'G;s,\(.*/\).*\n\1.*,\1,;h;$!d;s,/$,,' )

DOCKER_RUN := docker run -it --privileged --rm                        \
			--hostname sysbox-test                        \
			--name sysbox-test                            \
			-v $(CURDIR):$(PROJECT)                       \
			-v $(TEST_VOL1):/var/lib/docker               \
			-v $(TEST_VOL2):/var/lib/sysbox               \
			-v $(TEST_VOL3):/mnt/scratch                  \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			-v /lib/modules/$(KERNEL_REL):/lib/modules/$(KERNEL_REL):ro \
			-v /usr/src/$(HEADERS):/usr/src/$(HEADERS):ro \
			-v /usr/src/$(HEADERS_BASE):/usr/src/$(HEADERS_BASE):ro \
			$(TEST_IMAGE)


##@ Testing targets

test: ## Run all sysbox tests suites
test: test-fs test-mgr test-runc test-sysbox test-sysbox-shiftuid

test-sysbox: ## Run sysbox integration tests
test-sysbox: test-img
	@printf "\n** Running sysbox integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"

test-sysbox-shiftuid: ## Run sysbox integration tests with uid-shifting
test-sysbox-shiftuid: test-img
	@printf "\n** Running sysbox integration tests (with uid shifting) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export SHIFT_UIDS=true && testContainerInit && make test-sysbox-local TESTPATH=$(TESTPATH)"

test-runc: ## Run sysbox-runc unit & integration tests
test-runc: sysbox-ipc
	@printf "\n** Running sysbox-runc unit & integration tests **\n\n"
	cd $(SYSRUNC_DIR) && make clean && make BUILDTAGS="$(SYSRUNC_BUILDTAGS)" test

test-fs: ## Run sysbox-fs unit tests
test-fs: test-img
	@printf "\n** Running sysbox-fs unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-fs-local"

test-mgr: ## Run sysbox-mgr unit tests
test-mgr: test-img
	@printf "\n** Running sysbox-mgr unit tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make --no-print-directory test-mgr-local"

test-shiftfs: ## Run shiftfs tests
test-shiftfs: test-img
	@printf "\n** Running shiftfs tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "make test-shiftfs-local TESTPATH=$(TESTPATH)"
	$(DOCKER_RUN) /bin/bash -c "make test-shiftfs-ovfs-local TESTPATH=$(TESTPATH)"
	$(DOCKER_RUN) /bin/bash -c "make test-shiftfs-tmpfs-local TESTPATH=$(TESTPATH)"

test-shiftfs-cleanup: ## Cleanup shiftfs test suite
test-shiftfs-cleanup: pjdfstest-clean

test-shell: ## Get a shell in the test container (useful for debug)
test-shell: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "testContainerInit && /bin/bash"

test-shell-shiftuid: ## Get a shell in the test container with uid-shifting
test-shell-shiftuid: test-img
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_RUN) /bin/bash -c "export SHIFT_UIDS=true && testContainerInit && /bin/bash"

test-img: ## Build test container image
test-img:
	@printf "\n** Building the test container **\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_IMAGE) \
		-f Dockerfile.$(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE) .

test-cleanup: ## Clean up sysbox integration tests (to be run as root)
test-cleanup: test-img
	@printf "\n** Cleaning up sysbox integration tests **\n\n"
	$(DOCKER_RUN) /bin/bash -c "testContainerCleanup"
	$(TEST_DIR)/scr/testContainerPost $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)


#
# Local test targets (these are invoked from within the test container
# by the test target above); in theory they can run directly on a host
# machine, but they require root privileges and might messup the state
# of the host.
#

test-sysbox-local:
	$(TEST_DIR)/scr/testSysbox $(TESTPATH)

test-shiftfs-local: pjdfstest
	@printf "\n** shiftfs only mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs /var/lib/sysbox $(TESTPATH)

test-shiftfs-ovfs-local: pjdfstest
	@printf "\n** shiftfs + overlayfs mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs -m overlayfs /var/lib/sysbox $(TESTPATH)

test-shiftfs-tmpfs-local: pjdfstest
	@printf "\n** shiftfs + tmpfs mount **\n\n"
	$(SHIFTFS_DIR)/tests/testShiftfs -m tmpfs /var/lib/sysbox $(TESTPATH)

test-fs-local: sysbox-ipc
	cd $(SYSFS_DIR) && go test -timeout 3m -v $(fsPkgs)

test-mgr-local: sysbox-ipc
	dockerd > /var/log/dockerd.log 2>&1 &
	sleep 2
	cd $(SYSMGR_DIR) && go test -timeout 3m -v $(mgrPkgs)


#
# Test Sysbox Installer targets
#
# These targets run tests within a privileged test container that has
# systemd running and inside of which the Sysbox package is installed
# (just as it would be on a regular host).
#

DOCKER_RUN_INSTALLER := docker run -d --rm --privileged               \
			--hostname sysbox-installer-test              \
			--name sysbox-installer-test                  \
			-v $(CURDIR):$(PROJECT)                       \
			-v /lib/modules:/lib/modules:ro               \
			-v $(TEST_VOL1):/var/lib/docker               \
			-v $(TEST_VOL2):/var/lib/sysbox               \
			-v $(TEST_VOL3):/mnt/scratch                  \
			-v $(GOPATH)/pkg/mod:/go/pkg/mod              \
			--mount type=tmpfs,destination=/run           \
			--mount type=tmpfs,destination=/run/lock      \
			--mount type=tmpfs,destination=/tmp           \
			$(TEST_INSTALLER_IMAGE)


DOCKER_EXEC_INSTALLER := docker exec -it sysbox-installer-test
DOCKER_STOP_INSTALLER := docker stop sysbox-installer-test

##@ Installer Testing targets

test-installer: ## Run all sysbox's integration tests suites on the installer container
test-installer: test-sysbox-installer test-sysbox-shiftuid-installer

test-sysbox-installer: ## Run sysbox's integration tests on the installer container
test-sysbox-installer:
	make test-cntr-installer
	@printf "\n** Running sysbox integration tests **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_EXEC_INSTALLER) make sysbox-runc-recvtty
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "cat /etc/docker/daemon.json | \
		jq '. + {\"userns-remap\": \"sysbox\"}' > /tmp/daemon.json && \
		mv /tmp/daemon.json /etc/docker/daemon.json && \
		systemctl restart docker.service"
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "export SB_INSTALLER=true && \
		make test-sysbox-local TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP_INSTALLER)

test-sysbox-shiftuid-installer: ## Run sysbox's uid-shifting integration tests on the installer container
test-sysbox-shiftuid-installer:
	make test-cntr-installer
	@printf "\n** Running sysbox-installer integration tests (with uid shifting) **\n\n"
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_EXEC_INSTALLER) make sysbox-runc-recvtty
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "export SB_INSTALLER=true SHIFT_UIDS=true && \
		make test-sysbox-local TESTPATH=$(TESTPATH)"
	$(DOCKER_STOP_INSTALLER)

test-shell-installer: ## Get a shell in the installer container (useful for debug)
test-shell-installer: test-img-installer test-cntr-installer
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_EXEC_INSTALLER) make sysbox-runc-recvtty
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "cat /etc/docker/daemon.json | \
		jq '. + {\"userns-remap\": \"sysbox\"}' > /tmp/daemon.json && \
		mv /tmp/daemon.json /etc/docker/daemon.json && \
		systemctl restart docker.service"
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "export SB_INSTALLER=true && bash"
	$(DOCKER_STOP_INSTALLER)

test-shell-shiftuid-installer: ## Get a shell in the installer container with uid-shifting enabled (useful for debug)
test-shell-shiftuid-installer: test-cntr-installer
	$(TEST_DIR)/scr/testContainerPre $(TEST_VOL1) $(TEST_VOL2) $(TEST_VOL3)
	$(DOCKER_EXEC_INSTALLER) make sysbox-runc-recvtty
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "export SB_INSTALLER=true SHIFT_UIDS=true && bash"
	$(DOCKER_STOP_INSTALLER)

test-cntr-installer: ## Launch the installer container and build & install sysbox package
test-cntr-installer: test-img-installer
        # TODO: Stop / eliminate container if already running.
	$(DOCKER_RUN_INSTALLER)
ifeq (,$(wildcard $(IMAGE_FILE_PATH)/$(IMAGE_FILE_NAME)))
	@printf "\n** Cleaning previously built artifacts **\n\n"
	@make image clean
	@printf "\n** Building the sysbox deb package installer **\n\n"
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "sleep 10 && \
		make image build-deb $(IMAGE_BASE_DISTRO)-$(IMAGE_BASE_RELEASE)"
endif
	@printf "\n** Installing sysbox deb package **\n\n"
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "rm -rf /usr/sbin/policy-rc.d && \
		DEBIAN_FRONTEND=noninteractive dpkg -i $(IMAGE_FILE_PATH)/$(IMAGE_FILE_NAME)"
        # Some tests require that the Docker default runtime be set to sysbox-runc
	$(DOCKER_EXEC_INSTALLER) /bin/bash -c "cat /etc/docker/daemon.json | \
		jq '. + {\"default-runtime\": \"sysbox-runc\"}' > /tmp/daemon.json && \
		mv /tmp/daemon.json /etc/docker/daemon.json && \
		systemctl restart docker.service"

test-img-installer: ## Build installer container image
test-img-installer: test-img
	@printf "\n** Building the test-installer container image**\n\n"
	@cd $(TEST_DIR) && docker build -t $(TEST_INSTALLER_IMAGE) \
		-f $(TEST_INSTALLER_DOCKERFILE) .

#
# Misc targets
#

# recvtty is a tool inside the sysbox-runc repo that is needed by some integration tests
sysbox-runc-recvtty:
	@cd $(SYSRUNC_DIR) && make recvtty


#
# Images targets
#

##@ Images handling targets

image: ## Image creation / elimination sub-menu
	$(MAKE) -C $@ --no-print-directory $(filter-out $@,$(MAKECMDGOALS))

#
# Misc targets
#

# must run as root
pjdfstest: $(SHIFTFS_DIR)/pjdfstest/pjdfstest
	cp shiftfs/pjdfstest/pjdfstest /usr/local/bin

$(SHIFTFS_DIR)/pjdfstest/pjdfstest:
	cd shiftfs/pjdfstest && autoreconf -ifs && ./configure && make pjdfstest

pjdfstest-clean:
	cd $(SHIFTFS_DIR)/pjdfstest && ./cleanup.sh

listRuncPkgs:
	@echo $(runcPkgs)

listFsPkgs:
	@echo $(fsPkgs)

listMgrPkgs:
	@echo $(mgrPkgs)

#
# cleanup targets
#

##@ Cleaning targets

clean: ## Eliminate sysbox binaries
clean:
	cd $(SYSRUNC_DIR) && make clean
	cd $(SYSFS_DIR) && make clean
	cd $(SYSMGR_DIR) && make clean
	cd $(SYSIPC_DIR) && make clean

clean_libseccomp: ## Clean libseccomp
clean_libseccomp:
	cd $(LIBSECCOMP_DIR) && make clean

# memoize all packages once

_runcPkgs = $(shell cd $(SYSRUNC_DIR) && go list ./... | grep -v vendor)
runcPkgs = $(if $(__runcPkgs),,$(eval __runcPkgs := $$(_runcPkgs)))$(__runcPkgs)

_fsPkgs = $(shell cd $(SYSFS_DIR) && go list ./... | grep -v vendor)
fsPkgs = $(if $(__fsPkgs),,$(eval __fsPkgs := $$(_fsPkgs)))$(__fsPkgs)

_mgrPkgs = $(shell cd $(SYSMGR_DIR) && go list ./... | grep -v vendor)
mgrPkgs = $(if $(__mgrPkgs),,$(eval __mgrPkgs := $$(_mgrPkgs)))$(__mgrPkgs)
