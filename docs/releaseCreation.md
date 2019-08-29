Sysboxd's Releasing Process
===========================

During the execution of the following steps, no change should be pushed to any of the following repositories:

- sysboxd
- sysbox-fs
- sysbox-ipc
- sysbox-mgr
- sysbox-runc
- shiftfs
- fuse
- sysboxd-staging
- sysboxd-external

# Sysboxd repository changes

1) Create a new workspace from scratch:

    ```
    $ git clone --recursive git@github.com:nestybox/sysboxd.git
    ```

2) Create new release branch (the name itself doesn't really matter):

    ```
    $ git checkout -b release_v0.1.0 master
    ```

3) Increase release version in VERSION file.

4) Populate the CHANGELOG.md file with the desired entries. If there's a latest entry present as a placeholder for the upcoming release, make sure 
that the "UNRELEASED" attribute is eliminated.

3) Commit above changes locally.

    ```
    $ git add VERSION
    $ git add CHANGELOG.md
    $ git commit -m "Release v0.1.0"
    ```

4) Create a new annotated-tag corresponding to the release that we want to create (which should be matching the one added to VERSION file)

    ```
    $ git tag -a v0.1.0 -m "Release v0.1.0"
    ```

    Verify that tag was properly created:

    ```
    $ git tag -l -n3
    v0.0.1          Initial (private) release
    v0.1.0          Release v0.1.0
    ```

    Verify that the tag is properly pointing to the commit-id previously created in 3):

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
    $ dpkg -x images/deb/debbuild/ubuntu-bionic/sysboxd_0.1.0-0~ubuntu-bionic_amd64.deb sysboxd-deb-data
    $ gunzip -c sysboxd-deb-data/usr/share/doc/sysboxd/changelog.Debian.gz
    ```

7) Test image:

    ```
    $ sudo dpkg -i images/deb/debbuild/ubuntu-bionic/sysboxd_0.1.0-0~ubuntu-bionic_amd64.deb
    ```

8) Push above changes as well as the newly generated tag:

    ```
    $ git push origin release_v0.1.0 --follow-tags
    ```

9) Rebase-merge changes from Github's web-UI into sysboxd's master branch.


# Sysboxd-staging/external repository changes.

## Sysboxd-staging vs Sysboxd-external

Sysboxd-staging's goal is to serve as a staging ground for the changes that will be eventually published to sysboxd-external repository.

To simplify the synchronization task between sysboxd-staging and his public counterpart, we will always perform changes over sysboxd-staging, and will only write to sysboxd-external once that the git-log history in sysboxd-staging has been properly arranged to display one single entry per release milestone. See example below:

sysboxd-staging:

    ```
    $ git log --oneline
    1303bc7 (HEAD -> release_v0.1.0, tag: v0.1.0, sysboxd-external/new_v0.1.0, sysboxd-external/master) Release v0.1.0
    51fbe06 Internal release v0.0.1 (for testing purposes)
    ```

sysbox-external:

    ```
    $ git log --oneline
    1303bc7 (HEAD -> master, tag: v0.1.0, origin/release_v0.1.0_external, origin/master, origin/HEAD) Release v0.1.0
    51fbe06 Internal release v0.0.1 (for testing purposes)
    ``` 

## Releasing steps (sysboxd-staging)

1) Clone sysboxd-staging into a new workspace:

    ```
    $ git clone git@github.com:nestybox/sysboxd-staging.git
    ```

2) Create a new release branch (again, the name doesn't really matter):

    ```
    $ git checkout -b release_v0.1.0 master
    ```


3) Replace this repo's CHANGELOG.md file with the one from sysboxd's repository:

    ```
    rmolina@dev-bionic:~/wsp/08-27-2019/sysboxd-staging$ cp ../sysboxd/CHANGELOG.md .
    ```

3) Commit above change locally.

    ```
    $ git add CHANGELOG.md
    $ git commit -m "Release v0.1.0"
    ```

4) Rewrite git-log history to make sure all the entries created since the previous release are
all bundled into a single commit-id:

    ```
    $ git rebase -i HEAD~3  [ where '3' indicates how many commits we want to squash ]
    ```

5) As we did in sysboxd's repo, create a new annotated-tag corresponding to the release that we
want to create (which should be matching the one added in sysboxd's repo).

    ```
    $ git tag -a v0.1.0 -m "Release v0.1.0"
    ```

6) Verify that the just-created tag is pointing to the commit-id of our new release commit-id (the one
in step 4)

    ```
    $ git show v0.1.0
    ``` 

7) Push the CHANGELOG.md changes, the new tag, and the git-log modifications into sysboxd-staging remote:

    ```
    $ git push origin release_v0.1.0 --follow-tags
    ```

## Releasing steps (sysboxd-external)

8) Within sysboxd-staging workspace (step 7 above), add a new remote corresponding to sysboxd-external repository:

    ```
    $ git remote add sysboxd-external git@github.com:nestybox/sysboxd-external.git
    ```

9) Fetch sysboxd-external latest changes in master branch:

    ```
    $ git fetch sysboxd-external master
    ```

10) Create a new branch based off of sysboxd-external's master:

    ```
    git checkout -b release_v0.1.0_external remotes/sysboxd-external/master
    ```

11) Cherry-pick the commit-id previously pushed into sysboxd-staging corresponding to the new release being created:

    ```
    $ git log release_v0.1.0 --oneline
    $ git cherry-pick <commit-id>
    ```

12) Push the changes (should be a single commit-id) into sysboxd-external's remote:

    ```
    git push sysboxd-external release_v0.1.0_external --follow-tags
    ```

# Upload images

At this point this is a manual process that entails copying every *.deb file and adding into the release
section of sysboxd-external's repository. This process should be optimized soon.