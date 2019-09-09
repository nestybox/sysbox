# Sysbox's Image Creation Process

This document describes the process to follow to create a Sysbox
image that can be installed through regular package-management
utilities (i.e., dpkg and rpm).

We will start by outlining the basic steps being required, and will
later on provide a high-level description of the image-generation
framework, as well as the installer, that we will be utilizing.

## Image Creation Sequence

* Make sure that all temporary data from previously-generated
builds is fully eliminated:

    ```
    $ make image clean
    ```

* Build the desire image:

    ```
    $ make image build-deb
    make -C images --no-print-directory build-deb
    make -C deb

    Usage:
        make image build-deb <target>

    DEB building targets
      debian                     Build all Debian deb packages
      debian-buster              Build Debian Buster (10) packages
      debian-stretch             Build Debian Buster (9) packages
      ubuntu                     Build all Ubuntu deb packages
      ubuntu-disco               Build Ubuntu Disco (19.04) deb packages
      ubuntu-cosmic              Build Ubuntu Cosmic (18.10) deb packages
      ubuntu-bionic              Build Ubuntu Bionic (18.04) deb packages

    $ make image build-deb ubuntu-disco
    ```

* Generated artifacts will be placed on the following path:

    ```
    $ ls -lrt images/deb/debbuild/ubuntu-disco/
    -rw-r--r-- 1 rodny rodny 49425137 Jul 29 20:45 sysbox_0.0.1-0~ubuntu-disco.tar.gz
    -rw-r--r-- 1 rodny rodny      660 Jul 29 20:45 sysbox_0.0.1-0~ubuntu-disco.dsc
    -rw-r--r-- 1 rodny rodny 10361544 Jul 29 20:48 sysbox_0.0.1-0~ubuntu-disco_amd64.deb
    -rw-r--r-- 1 rodny rodny  6187744 Jul 29 20:48 sysbox-dbgsym_0.0.1-0~ubuntu-disco_amd64.ddeb
    -rw-r--r-- 1 rodny rodny     5348 Jul 29 20:48 sysbox_0.0.1-0~ubuntu-disco_amd64.buildinfo
    -rw-r--r-- 1 rodny rodny     1949 Jul 29 20:48 sysbox_0.0.1-0~ubuntu-disco_amd64.changes
    $
    ```

    Note that these artifacts correspond to the typical elements produced during
    debian packages compilation. For obvious reasons, we will be only sharing
    the *.deb file (i.e. binary package) with our potential clients.

* Copy the obtained *.deb file to the desired DUT, and install it accordingly.

    ```
    $ sudo dpkg -i sysbox_0.0.1-0~ubuntu-disco_amd64.deb
    Selecting previously unselected package sysbox.
    (Reading database ... 150254 files and directories currently installed.)
    Preparing to unpack .../sysbox_0.0.1-0~ubuntu-disco_amd64.deb ...
    Unpacking sysbox (1:0.0.1-0~ubuntu-disco) ...
    Setting up sysbox (1:0.0.1-0~ubuntu-disco) ...

    Disruptive changes made to docker configuration. Restarting docker service...
    Created symlink /etc/systemd/system/sysbox.service.wants/sysbox-fs.service → /lib/systemd/system/sysbox-fs.service.
    Created symlink /etc/systemd/system/sysbox.service.wants/sysbox-mgr.service → /lib/systemd/system/sysbox-mgr.service.
    Created symlink /etc/systemd/system/multi-user.target.wants/sysbox.service → /lib/systemd/system/sysbox.service.
    ```

* If package installation succeeded in the previous step, Sysbox's daemons
should be running by now...

    ```
    $ systemctl list-units -t service --all | grep sysbox
    sysbox-fs.service                   loaded    active   running Sysbox-fs component
    sysbox-mgr.service                  loaded    active   running Sysbox-mgr component
    sysbox.service                      loaded    active   exited  Sysbox General Service
    ```


# Image Creation Framework

Let's briefly discuss the framework utilized to create Sysbox images.

What follows is a graphical representation of the elements that conform this
framework, and a brief description of their goals.

```
VERSION                          // Version number to utilize by all software components
images                           // Image-creation sub-tree
├── deb                          // Debian-specific instructions
│   ├── build-deb                // Bash-script to orchestrate debian-images generation
│   ├── common                   // Debian package installation logic
│   │   ├── compat
│   │   ├── control              // Debian regular control file
│   │   ├── rules                // Debian regular rules file
│   │   ├── sysbox.config
│   │   ├── sysbox.install
│   │   ├── sysbox.manpages
│   │   ├── sysbox.postinst
│   │   ├── sysbox.postrm
│   │   ├── sysbox.preinst
│   │   └── sysbox.templates
│   ├── debian-buster            // Debian-Buster image builder container
│   │   └── Dockerfile
│   ├── debian-stretch           // Debian-Stretch image builder container
│   │   └── Dockerfile
│   ├── Makefile
│   ├── ubuntu-bionic            // Ubuntu-Bionic image builder container
│   │   └── Dockerfile
│   ├── ubuntu-cosmic            // Ubuntu-Cosmic image builder container
│   │   └── Dockerfile
│   └── ubuntu-disco             // Ubuntu-Disco image builder container
│       └── Dockerfile
├── Makefile                     // Top-most makefile to drive both *.deb and *.rpm image creations
├── rpm                          // RPM-specific instructions (TBD)
│   └── Makefile
└── systemd                      // Systemd's units corresponding to Sysbox's daemons
    ├── sysbox-fs.service
    ├── sysbox-mgr.service
    ├── sysbox.service
    └── sysbox-systemd.conf
```

In a nutshell, these are the tasks carried out by this building infrastructure:

* Instantiate a slave container matching the linux distro/version being required.
Even though Sysbox currently only supports Ubuntu releases, this logic is capable
of generating Sysbox images for all these releases:

    - Ubuntu-Disco
    - Ubuntu-Cosmic
    - Ubuntu-Bionic
    - Debian-Buster
    - Debian-Stretch

* Create a 'shiftfs-dkms' debian package containing the elements required for its
compilation.

* Install previous 'shiftfs-dkms' debian package into the slave container, and
generate, by virtue of dkms processing, the shiftfs kernel modules for all the
(5.x+) kernel releases supported by each supported distro.

* Create Sysbox debian package including the shiftfs module built above, as
well as the Sysbox package installer.


# Installer/Uninstaller Overview

Sysbox's installer/uninstaller takes care of the following tasks...

* Queries user for feedback regards his desire to restart dockerd
manually/automatically should the installer consider it appropriated.

* Verify that Sysbox is being installed over a supported Linux
distribution and a supported Linux kernel.

* Creates sysbox-fs mountpoint.

* Allows unprivileged users to create user namespaces.

* Adds/Deletes 'sysbox' user for scenarios demanding the
utilization of 'userns-remap' knob (i.e. kernels < 5.0).

* Loads/Unloads uid-shifting kernel module in supported scenarios
(i.e. kernels >= 5.0).

* Creates/Adjusts docker config file in order to:
    - Create/Delete a 'sysbox' userns-remap entry.
    - Add/Delete sysbox-runc runtime entry.

* Restart/Sighup dockerd to have daemon.json changes being absorbed.

* Create/Delete sysbox's systemd service in charge of managing
sysbox-fs and sysbox-mgr daemons.
