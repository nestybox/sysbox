Sysbox's Releasing Process
===========================

During the execution of the following steps, no change should be pushed to any of
the following repositories:

- sysbox
- sysbox-fs
- sysbox-ipc
- sysbox-mgr
- sysbox-runc
- shiftfs
- fuse
- sysbox-staging
- sysbox-external

# Sysbox repository changes

1) Create a new workspace from scratch:

    ```
    $ git clone --recursive git@github.com:nestybox/sysbox.git
    ```

2) Create new release branch (the name itself doesn't really matter):

    ```
    $ git checkout -b release_v0.1.0 master
    ```

3) Increase release version in VERSION file.

4) Populate the CHANGELOG.md file with the desired entries. If there's a latest
entry present as a placeholder for the upcoming release, make sure that the
"UNRELEASED" attribute is eliminated.

3) Commit above changes locally.

    ```
    $ git add VERSION
    $ git add CHANGELOG.md
    $ git commit -m "Release v0.1.0"
    ```

4) Create a new annotated-tag corresponding to the release that we want to create
(which should be matching the one added to VERSION file)

    ```
    $ git tag -a v0.1.0 -m "Release v0.1.0"
    ```

    Verify that tag was properly created:

    ```
    $ git tag -l -n3
    v0.0.1          Initial (private) release
    v0.1.0          Release v0.1.0
    ```

    Verify that the tag is properly pointing to the commit-id previously created
    in 3):

    ```
    $ git show v0.1.0
    ```

5) Build supported images:
    
    ```
    $ make image build-deb ubuntu-bionic
    $ make image build-deb ubuntu-cosmic
    $ make image build-deb ubuntu-disco
    ```

6) Verify generated debian-changelog matches our expectations:

    ```
    $ dpkg -x images/deb/debbuild/ubuntu-bionic/sysbox_0.1.0-0~ubuntu-bionic_amd64.deb sysbox-deb-data
    $ gunzip -c sysbox-deb-data/usr/share/doc/sysbox/changelog.Debian.gz
    ```

7) Test image:

    ```
    $ sudo dpkg -i images/deb/debbuild/ubuntu-bionic/sysbox_0.1.0-0~ubuntu-bionic_amd64.deb
    ```

8) Push above changes as well as the newly generated tag:

    ```
    $ git push origin release_v0.1.0 --follow-tags
    ```

9) Rebase-merge changes from Github's web-UI into sysbox's master branch.

10) Test generated images in the corresponding VM:

    * We must scp all generated images to the matching VM -- see examples below:

    Ubuntu-Bionic-VM:

    ```
    rmolina@dev-vm1:~/wsp/release_v0.2.0_new/sysbox$ scp -P 40122 image/deb/debbuild/ubuntu-bionic/sysbox_0.2.0-0.ubuntu-bionic_amd64.deb vagrant@192.168.1.2:~/wsp/v0.2.0/sysbox/image/deb/debbuild/ubuntu-bionic/
    ```

    Ubuntu-Eoan-VM:

    ```
    rmolina@dev-vm1:~/wsp/release_v0.2.0_new/sysbox$ scp -P 40422 image/deb/debbuild/ubuntu-eoan/sysbox_0.2.0-0.ubuntu-eoan_amd64.deb vagrant@192.168.1.2:~/wsp/v0.2.0/sysbox/image/deb/debbuild/ubuntu-eoan/
    ```

    Ubuntu-Focal-VM:

    ```
    rmolina@dev-vm1:~/wsp/release_v0.2.0_new/sysbox$ scp -P 40522 image/deb/debbuild/ubuntu-focal/sysbox_0.2.0-0.ubuntu-focal_amd64.deb vagrant@192.168.1.2:~/wsp/v0.2.0/sysbox/image/deb/debbuild/ubuntu-focal/
    ```

    * From each VM, do a git-clone of sysbox's entire repo, and then copy the
    previous sysbox debian package into the path expected by the "test-installer"
    integration suite.

    Example for Ubuntu-Bionic-VM:

    ```
    vagrant@ubuntu-bionic-vm:~/wsp/v0.1.3/sysbox$ cp ../sysbox_0.1.3-0.ubuntu-bionic_amd64.deb image/deb/debbuild/ubuntu-bionic/
    ```

    * Launch the "test-installer" integration suite for each of the VMs:

    Example for Ubuntu-Bionic-VM:

    ```
    vagrant@ubuntu-bionic-vm:~/wsp/v0.1.3/sysbox$ make test-installer
    ```

11) Collect and store all generated test-output into sysbox/test/output/ folder.

# Sysbox-staging/external repository changes.

## Sysbox-staging vs Sysbox-external

Sysbox-staging's goal is to serve as a staging ground for the changes that will be
eventually published to sysbox-external repository.

To simplify the synchronization task between sysbox-staging and his public
counterpart, we will always perform changes over sysbox-staging, and will only
write to sysbox-external once that the git-log history in sysbox-staging has been
properly arranged to display one single entry per release milestone. See example
below:

sysbox-staging:

    ```
    $ git log --oneline
    1303bc7 (HEAD -> release_v0.1.0, tag: v0.1.0, sysbox-external/new_v0.1.0, sysbox-external/master) Release v0.1.0
    51fbe06 Internal release v0.0.1 (for testing purposes)
    ```

sysbox-external:

    ```
    $ git log --oneline
    1303bc7 (HEAD -> master, tag: v0.1.0, origin/release_v0.1.0_external, origin/master, origin/HEAD) Release v0.1.0
    51fbe06 Internal release v0.0.1 (for testing purposes)
    ``` 

## Releasing steps (sysbox-staging)

1) Clone sysbox-staging into a new workspace:

    ```
    $ git clone git@github.com:nestybox/sysbox-staging.git
    ```

2) Create a new release branch (again, the name doesn't really matter):

    ```
    $ git checkout -b release_v0.1.0 master
    ```


3) Replace this repo's CHANGELOG.md file with the one from sysbox's repository:

    ```
    rmolina@dev-bionic:~/wsp/08-27-2019/sysbox-staging$ cp ../sysbox/CHANGELOG.md .
    ```

3) Commit above change locally.

    ```
    $ git add CHANGELOG.md
    $ git commit -m "Release v0.1.0"
    ```

4) Rewrite git-log history to make sure all the entries created since the previous
release are all bundled into a single commit-id:

    ```
    $ git rebase -i HEAD~3  [ where '3' indicates how many commits we want to squash ]
    ```

5) As we did in sysbox's repo, create a new annotated-tag corresponding to the
release that we want to create (which should be matching the one added in sysbox's
repo).

    ```
    $ git tag -a v0.1.0 -m "Release v0.1.0"
    ```

6) Verify that the just-created tag is pointing to the commit-id of our new release
commit-id (the one in step 4)

    ```
    $ git show v0.1.0
    ``` 

7) Push the CHANGELOG.md changes, the new tag, and the git-log modifications into
sysbox-staging remote:

    ```
    $ git push origin release_v0.1.0 --follow-tags
    ```

## Releasing steps (sysbox-external)

8) Within sysbox-staging workspace (step 7 above), add a new remote corresponding
to sysbox-external repository:

    ```
    $ git remote add sysbox-external git@github.com:nestybox/sysbox-external.git
    ```

9) Fetch sysbox-external latest changes in master branch:

    ```
    $ git fetch sysbox-external master
    ```

10) Create a new branch based off of sysbox-external's master:

    ```
    git checkout -b release_v0.1.0_external remotes/sysbox-external/master
    ```

11) Cherry-pick the commit-id previously pushed into sysbox-staging corresponding
to the new release being created:

    ```
    $ git log release_v0.1.0 --oneline
    $ git cherry-pick <commit-id>
    ```

12) Push the changes (should be a single commit-id) into sysbox-external's remote:

    ```
    git push sysbox-external release_v0.1.0_external --follow-tags
    ```

# Upload images

At this point this is a manual process that entails copying every *.deb file and
adding into the release section of sysbox-external's repository. This process
should be optimized soon.

# nbox-shiftfs-staging/external repository changes.

As part of the releasing process we must also generate a tag for nbox-shiftfs
repositories, as shiftfs code and the associated documentation is subject to
change at any point in time.

The sequence of steps to follow to update these two repos is pretty much identical
to the one we went through for sysbox-staging/external, so please refer to the
above section for the details.