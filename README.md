# Shaka

**Give your coding agent a task. Get a tested, reviewed PR that's easy to understand.**

Shaka guides your agent through implementation, local testing, independent review,
and delivery on GitHub. You describe the outcome; Shaka supplies the workflow.

[Read the Shaka documentation](https://shaka.shakacode.com/).

Shaka brings back a PR ready to merge, asks for a decision when needed, or merges
automatically when authorized and required checks and approvals pass.

## Example prompts

```text
$shaka Fix search when the query contains an apostrophe.
```

Shaka checks for existing work, considers whether the change is worth doing, and
recommends a model and effort level. You can also give it an issue or task link:

```text
$shaka https://linear.app/your-team/issue/APP-123/fix-search
Use Sol, medium effort. Go.
```

Replace the example link and choose a model available in your coding agent.
You can also say `Go` without restating model or effort: Shaka starts when its
recommendation matches the model and effort your agent reports as active. If they
differ or the agent cannot confirm them, Shaka asks you to choose or confirm.
It still brings you decisions that need your input.

## Why use it?

- **Spend less time directing the process.** Describe the outcome. Shaka supplies
  the steps through testing, review, and PR delivery.
- **Catch problems before hitting CI.** Test and review locally, including adversarial
  reviews and before-and-after screenshots for UI changes. Fix problems before pushing.
- **Make review easier.** Get a PR that's easy to review with a clear description. Screenshots
  show visible changes; a code walkthrough explains implementation choices.
- **See what a PR cost.** See available token usage and estimated cost, including
  implementation and local review data.
- **Control merging.** Choose **Ask** to merge yourself or **Auto** to let the agent
  merge after required checks and approvals. Consequential changes need human review.
- **Resume unfinished work easily.** WIP Details on the PR identify the owning agent chat,
  where it stopped, and what comes next. Supported chat links take you back to the
  owning conversation.
- **Use your existing tools.** Shaka works with your coding agent, repository scripts,
  and GitHub.

## Get started

[Install Shaka and configure your repository](docs/getting-started.md)
with simple prompts.

### Requirements

Ruby 3.4 or later, Git, an authenticated [GitHub CLI](https://cli.github.com/), and
[a coding agent](docs/coding-agents.md) that can load skills and run commands.
Optional: ImageMagick 7, so agents can add a
[difference image](docs/pr-verification.md#show-what-changed-between-captures)
to UI changes.
Shaka waits for CI checks that GitHub requires or that you list in its settings;
see [before you start](docs/configure-repository.md#before-you-start).

## How it works

- **Enforcement.** Ruby and GitHub check configuration, comment trust, and merge
  conditions. The [enforcement reference](docs/workflow.md#what-is-enforced)
  identifies which steps rely on the agent.
- **A shared workflow.** The skill guides each task through planning,
  implementation, verification, review, and delivery. Repository settings supply
  your commands and merge preferences.
- **Verification.** [Tests, independent review, and visual comparisons](docs/pr-verification.md)
  show whether the work is ready. Shaka gives your agent explicit checkpoints for
  testing, review, and delivery.

## Public review safety

Shaka reads feedback from trusted reviewers and leaves other comments for
maintainer triage.

## Documentation

- [Architecture](docs/architecture.md) — why Shaka keeps one owner and little state.
- [Getting started](docs/getting-started.md) — install, configure, and run a task.
- [Working with Shaka](docs/working-with-shaka.md) — merge policy, feedback, and resuming work.
- [Repository setup](docs/configure-repository.md) and [settings](docs/settings.md).
- [Documentation index](docs/README.md) — all product guides.

[Skill references](skills/shaka/references/README.md) · [Contributing](CONTRIBUTING.md) · [MIT license](LICENSE)
