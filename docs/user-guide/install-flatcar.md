# Flatcar Installation

The document outlines the set of instructions that are required to install Sysbox
on Kinvolk's Flatcar Linux distribution.

#### ** --- Sysbox-EE Feature Highlight --- **

Due to the enterprise-oriented nature of Flatcar's typical deployments, as well
as the extra maintenance cost that it entails from Sysbox maintainers, Flatcar
support is currently only offered as part of the Sysbox Enterprise Edition (EE).

***

## Contents

*   [Why Sysbox on Flatcar?](#why-sysbox-on-flatcar)
*   [Supported Flatcar Releases](#supported-flatcar-releases)
*   [Installing Sysbox on Flatcar](#installing-sysbox-on-flatcar)
*   [Sysbox Components](#sysbox-components)
*   [Contact](#contact)
*   [Thank You!](#thank-you)

## Why Sysbox on Flatcar?

Flatcar is a container-optimized Linux distro, meaning that the OS is designed
to run workloads inside containers efficiently and securely.

Running Sysbox on Flatcar further increases container security and flexibility,
as Sysbox enables containers deployed by Docker or Kubernetes to run with
stronger isolation (Linux user-namespace, procfs and sysfs virtualization,
initial mount locking, etc.). In addition, Sysbox enables containers to run most
workloads that run in virtual machines (including systemd, Docker, and even
Kubernetes), thus enabling new powerful use cases for containers beyond
microservice deployment.

## Supported Flatcar Releases

* 2905.2.3
* 2905.2.6

## Installing Sysbox on Flatcar

The method of installation depends on whether Sysbox is installed on
a Kubernetes node or a Docker host.

### Installing Sysbox on Flatcar Kubernetes Nodes

Sysbox Enterprise (EE) can be easily installed on Kubernetes nodes running Flatcar.
The installation method in this case fully matches the one of other distributions
supported by Sysbox. Please refer to [this](install-k8s.md) document for more
details.

### Installing Sysbox on Flatcar Docker Hosts

To install Sysbox on a host machine (physical or VM) running Flatcar, simply
use this [Container Linux configuration file](flatcar-config.yaml). This config
installs the [Sysbox components](#sysbox-components) on the Flatcar host.

**NOTE**: Add to the config file any other configurations you need for the machine
(e.g., users, ssh keys, etc.)

For example, the steps below deploy Sysbox on a Google Compute Engine (GCE)
virtual machine:

1) Add the ssh authorized key to the [flatcar-config.yaml](flatcar-config.yaml):

```yaml
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - "ssh-rsa AAAAB3NzaC1yc..."
```

2) Convert the config to the Ignition format. This is done using the `ct` tool,
as described [in this Kinvolk doc](https://kinvolk.io/docs/flatcar-container-linux/latest/provisioning/config-transpiler/):

```console
$ ct --platform=gce < flatcar-config.yaml > config.ign
```

3) Provision the GCE VM and pass the `config.ign` generated in the prior step as "user-data".

```console
$ gcloud compute instances create flatcar-vm --image-project kinvolk-public --image-family flatcar-stable --zone us-central1-a --machine-type n2-standard-4 --metadata-from-file user-data=config.ign
Created [https://www.googleapis.com/compute/v1/projects/predictive-fx-309900/zones/us-central1-a/instances/flatcar-vm].
NAME        ZONE           MACHINE_TYPE   PREEMPTIBLE  INTERNAL_IP    EXTERNAL_IP    STATUS
flatcar-vm  us-central1-a  n2-standard-4               10.128.15.196  34.132.170.36  RUNNING
```

When the VM boots, Sysbox will already be installed and running. You can verify
this as follows:

```console
core@flatcar-vm ~ $ systemctl status sysbox
● sysbox.service - Sysbox container runtime
     Loaded: loaded (/etc/systemd/system/sysbox.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2021-07-05 19:35:41 UTC; 3h 10min ago
       Docs: https://github.com/nestybox/sysbox
   Main PID: 1064 (sh)
      Tasks: 2 (limit: 19154)
     Memory: 704.0K
     CGroup: /system.slice/sysbox.service
             ├─1064 /bin/sh -c /opt/bin/sysbox/sysbox-runc --version && /opt/bin/sysbox/sysbox-mgr --version && /opt/bin/sysbox/sysbox-fs --version && /bin/sleep infinity
             └─1084 /bin/sleep infinity
```

You can now deploy containers with Docker + Sysbox as follows:

```console
core@flatcar-vm ~ $ docker run --runtime=sysbox-runc -it --rm <some-image>
```

This will create a container that is strongly secured and is capable of running
microservices as well as full OS environments (similar to a VM, but with the
efficiency and speed of containers).

For example, to deploy a "VM-like" container that runs Ubuntu Focal + systemd +
Docker inside:

```console
core@flatcar-vm ~ $ docker run --runtime=sysbox-runc -it --rm nestybox/ubuntu-focal-systemd-docker
```

Please refer the [Sysbox Quickstart Guide](https://github.com/nestybox/sysbox/tree/master/docs/quickstart)
and [Nestybox blog site](https://blog.nestybox.com/) for may more usage examples.

**NOTE:** If you exclude the `--runtime=sysbox-runc` flag, Docker will launch
containers with it's default runtime (aka runc). You can have regular Docker
containers live side-by-side and communicate with Docker + Sysbox containers
without problem.

## Sysbox Components

The [flatcar-config.yaml](flatcar-config.yaml) performs the following configurations on a Flatcar host:

* Places the Sysbox-EE binaries in a directory called `/opt/bin/sysbox`. The
  binaries include:

  - sysbox-mgr, sysbox-runc, sysbox-fs, the `shiftfs` module, and `fusermount`.

* Loads the `shiftfs` module into the kernel.

  - This module is present in Ubuntu kernels, but typically not present on other
    distros. It brings multiple functional benefits, such as giving Sysbox the
    ability to isolate containers with the Linux user-namespace without changes
    in Docker's configuration. More on shiftfs [here](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md#ubuntu-shiftfs-module).

* Configures some kernel sysctl parameters (the `flatcar-config.yaml` has the details).

* Installs and starts the Sysbox-EE systemd units.

* Configures Docker to learn about Sysbox-EE and restarts Docker.

The result is that the host is fully configured to run Docker containers
with Sysbox.
