# Sysbox Pods Tests

This directory contains tests that verify the functionality of K8s pods
deployed with Sysbox.

The tests use crictl + CRI-O + Sysbox to create and manage the pods. They **do
not** use K8s itself to create them (as we've not yet implemented support for
run K8s inside the test container; we could use K8s.io KinD or Minikube in the
future, but not sure if this will work).

The test container comes with crictl + CRI-O pre-installed and configured to use
Sysbox, so the tests need only issue crictl commands to generate the pods.
