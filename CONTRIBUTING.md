# Contribute to Sysbox

Want to contribute to Sysbox? Thanks, the Sysbox community welcomes your
contributions!

This page contains information about the process to contribute.

## Contents

-   [Reporting security issues](#reporting-security-issues)
-   [Reporting other issues](#reporting-other-issues)
-   [Documentation Changes](#documentation-changes)
-   [Developer's guide](#developers-guide)
-   [We welcome pull requests](#we-welcome-pull-requests)
-   [Criteria for accepting changes](#criteria-for-accepting-changes)
-   [Open-source vs. proprietary functionality](#open-source-vs-proprietary-functionality)
-   [Write clean code](#write-clean-code)
-   [Testing is super important](#testing-is-super-important)
-   [Please keep the documentation up to date](#please-keep-the-documentation-up-to-date)
-   [Process for creating pull requests](#process-for-creating-pull-requests)
-   [Sign your work](#sign-your-work)

## Reporting security issues

Strong container security is of upmost concern for Sysbox.

If you are reporting a security issue, please do not create an issue or file a
pull request on GitHub. Instead, disclose the issue responsibly by sending an
email to contact@nestybox.com.

## Reporting other issues

Please follow these guidelines when filing issues with Sysbox.

In all cases, first search existing issues, as it's likely the bug has already
been reported (and we want to avoid multiple bugs for the same issue).

### Bug Reports

* Create a GitHub issue with the label "Bug"

* Add a label corresponding to the Sysbox release (e.g. `v0.2.0`)

* Describe the issue as clearly and completely as possible.

* Describe how to best reproduce it.

* Include information about the host's Linux version (e.g., `lsb_release`, `uname -a`).

### Feature requests

* Create a GitHub issue with the label "Enhancement"

* Add a label corresponding to the Sysbox release (e.g. `v0.2.0`)

* Describe the need for the proposed enhancement.

* Provide a high-level description of the enhancement and its benefits.

### Documentation Changes

* Create a GitHub issue with the label "Documentation"

* Describe the need for the proposed documentation change.

## Developer's guide

If you wish to contribute code changes to Sysbox, the [developer's guide](docs/developers-guide/README.md)
has all the info to help you setup your environment for building and testing
Sysbox.

## We welcome pull requests

We appreciate your pull requests, as they help us improve Sysbox.

A pull request can fix or improve any aspect of Sysbox, from a minor
documentation typo to an important feature.

For pull requests that fix bugs, add features / functionality, or change
documentation in important ways, we ask that you first file an issue (see prior
section), such that the pull request can be coupled to that issue.

For minor changes (e.g., a small documentation typo, a small code refactoring,
adding a small test, etc.), you can file the pull request without filing an
issue for it.

If your pull request is not accepted on the first try, don't be discouraged. The
community will do its best to give you constructive feedback so you can improve
the pull request.

## Criteria for accepting changes

The Sysbox maintainers are in charge of approving pull requests.

They will do so based on:

* The need for the change.

* Whether the change meets the goals of Sysbox project's community.

* The quality of the change.

* The testing done (when appropriate).

## Open-source vs. proprietary functionality

To ensure synergy between the Sysbox project and companies that wish to build
products based on it (such as Nestybox), we use the following criteria when
considering adding functionality to Sysbox:

Any features that mainly benefit individual practitioners are made part of the Sysbox
open-source project. Any features that mainly address enterprise-level needs are
not part of the Sysbox open-source project.

The Sysbox maintainers will make this determination on a feature by feature
basis, with total transparency.

This way, the Sysbox open source project satisfies the needs of individual
practitioners while giving companies such as Nestybox the chance to monetize on
enterprise-level features (which in turn enables Nestybox to continue to sponsor
the Sysbox open source project).

## Write clean code

Write clean code (keep it simple, make it easy to understand for your fellow
contributors).

Sysbox is written in [Go](https://golang.org/). Always run `gofmt -s -w file.go`
on each changed file before committing your changes. Most editors have plugins
that do this automatically.

## Testing is super important

All functional changes to Sysbox must pass the Sysbox's regression test suite
before the pull request can be accepted.

In addition, changes that fix bugs or add new functionality must be accompanied
with a corresponding set of tests.

In Sysbox, tests are divided into two categories:

* Unit tests: written with Go's "testing" package.

* Integration tests: written using the [bats](https://github.com/sstephenson/bats) framework.

In general, having a combination of these is best, with unit tests performing
thorough testing (main code paths, corner-cases, etc) and integration tests
focusing on interaction of the target functionality with other aspects of Sysbox
or the rest of the system.

The [developer's guide](docs/developers-guide/README.md) has the info on how to run
Sysbox tests.

## Please keep the documentation up to date

Sysbox is a complex piece of software. As such, clear and concise documentation
describing its features and functionality is of upmost importance.

Please update the docs whenever:

* You see a mismatch between the document and existing functionality.

* You add a new feature.

* You change or remove an existing feature.

* You spot typos, missing docs, or unclear/incorrect docs.

And remember: the documentation is as important as the software itself.

## Process for creating pull requests

1) Fork the Sysbox repo

2) Make changes on your fork in a dedicated branch.

- Name it XXX-something where XXX is the number of the issue (e.g., "202-fix").

3) Test your changes (see [above](#testing-is-super-important).

4) Commit the changes in your branch

- Commit messages must start with a capitalized and short summary (max. 70
  chars) written in the imperative, followed by an optional, more detailed
  explanatory text which is separated from the summary by an empty line.

- For example:

  "Add a command line option to configure logging in sysbox-mgr.

  Add the "--log-level" option to the sysbox-mgr, to configure
  logging levels. We initially support the following log-levels ..."

- Sign-off the commit (see [next section](#sign-your-work)).

5) Submit the pull request.

- Pull requests descriptions should be as clear as possible and include a
  reference to all the issues that they address.

- Pull requests must not contain commits from other users or branches.

Code review comments may be added to your pull request. Discuss, then make the
suggested modifications and push additional commits to your feature branch. Be
sure to post a comment after pushing. The new commits will show up in the pull
request automatically, but the reviewers will not be notified unless you
comment.

Before the pull request is merged, make sure that you squash your commits into
logical units of work using `git rebase -i` and `git push -f`. After every
commit the test suite should be passing.

Include documentation changes in the same commit so that a revert would remove
all traces of the feature or fix.

Commits that fix or close an issue should include a reference like `Closes
#XXX` or `Fixes #XXX`.

## Sign your work

The sign-off is a simple line at the end of the explanation for the
patch, which certifies that you wrote it or otherwise have the right to
pass it on as an open-source patch.

The rules are pretty simple: if you can certify the below (from
[developercertificate.org](http://developercertificate.org/)):

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
660 York Street, Suite 102,
San Francisco, CA 94110 USA

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

then you just add a line to every git commit message:

    Signed-off-by: Joe Smith <joe@gmail.com>

using your real name (sorry, no pseudonyms or anonymous contributions.)

You can add the sign off when creating the git commit via `git commit -s`.
