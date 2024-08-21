# K8s.io KinD + Sysbox tests

The tests in this directory verify that the [K8s.io KinD](https://kind.sigs.k8s.io/)
tool works with Docker + Sysbox as the container runtime, such that each K8s
node is run in a (rootless) Sysbox container (as opposed to a privileged
container as KinD normally requires).
