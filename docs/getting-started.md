# Getting started

## 1. Install Shaka

Ask your coding agent:

```text
Install Shaka from https://github.com/shakacode/shaka for this coding agent.
Keep the installation outside the repositories I'll work on.
Follow its installation instructions and confirm the skill is available.
```

The agent checks for Ruby 3.4 or later, Git, and an authenticated GitHub CLI.
It also reports whether optional ImageMagick 7 is installed; with it, PRs for
UI changes can include a
[difference image](pr-verification.md#show-what-changed-between-captures).
Start a new chat if the skill does not appear. See [coding agents](coding-agents.md)
for environment-specific setup.

Installation keeps a managed copy of the Shaka skill and links your coding agent
to it. Shaka keeps using the Ruby that installed it, so a project that selects
an older Ruby or loads Bundler cannot stop it. You can remove the source checkout after installation; the skill and its
workflow still work. On upgrade, Shaka keeps the previous copy. To roll back
after removing the checkout, get a source checkout again and run its installer.
See [install and maintain Shaka](https://github.com/shakacode/shaka/blob/main/skills/shaka/references/installation.md)
for the procedure.

Use a source installation: the published gem is a name-reservation prerelease
without the current workflow.

### Use a personal fork

To customize Shaka and contribute improvements upstream:

```text
Fork https://github.com/shakacode/shaka into my GitHub account and install
Shaka from that fork. Keep upstream configured so we can pull updates
and submit improvements back to shakacode/shaka.
```

## 2. Configure your repository

Shaka waits for your CI checks. If GitHub does not require any, for example on a
private repository on the GitHub Free plan, setup lists them in the Shaka settings
instead. See [before you start](configure-repository.md#before-you-start).

Open a chat in your project:

```text
$shaka Configure this repository for Shaka. Inspect its existing checks
and suggest the settings. Keep merge policy ask.
```

The agent connects your existing commands to Shaka through a configuration file
and standard scripts—the repository **seam**. Review and merge its setup PR
before starting work. Shaka also offers setup when invoked in an unconfigured
repository. See [repository setup](configure-repository.md).

## 3. Start a task

```text
$shaka Fix search when the query contains an apostrophe. Go.
```

Describe the outcome or supply a task link. Shaka recommends a model and effort
level. Add `Go` to start immediately when those settings are already active and
your coding agent can confirm them. You can also choose them up front:

```text
$shaka Fix search when the query contains an apostrophe. Use Sol, medium effort. Go.
```

Choose an available model and activate it in your coding agent; the prompt does
not switch it for you. If its active settings differ from the recommendation or
cannot be confirmed, Shaka pauses for your choice or confirmation. Testing and
review are already part of the workflow.
See [working with Shaka](working-with-shaka.md) for merge choices and feedback.
