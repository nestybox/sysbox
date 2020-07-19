This directory contains tests that verify deploying a full K8s cluster inside a
single system container. That is, the sys container is acting as a virtual host
inside of which a K8s-in-docker cluster is deployed.

We call this "kubernetes-in-docker ... in docker" or "kindind" for short.

Such a setup is useful in environments where a sys admin wants to give users a
sys container based virtual host, and the users want to deploy K8s-in-Docker
inside (e.g., using the K8s.io kind tool).

Notice that this is different than launching a K8s cluster using sys containers
as K8s nodes (which is just KinD with sys containers).
