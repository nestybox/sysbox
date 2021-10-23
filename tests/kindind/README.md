This directory contains tests that verify deploying a full K8s cluster inside a
single sysbox container. That is, the sys container is acting as a virtual host
inside of which a K8s-in-docker cluster is deployed using the K8s.io KinD tool.

We call this "kubernetes-in-docker ... in docker" or "kindind" for short.

Such a setup is useful in CI environments where a job deploys a sysbox
container/pod, and inside of it an test K8s cluster is deployed.

Notice that this is different than launching a K8s cluster using sys containers
as K8s nodes (which is just KinD with sysbox containers).
