# Workflow and enforcement

Shaka supplies the process; your repository supplies the commands and constraints.

| Step | Result |
| --- | --- |
| Intake | Confirm the task, repository, ownership, and merge preference |
| Plan | Assess value, scope, risk, model, and effort |
| Implement | Reproduce bugs or test new behavior, then make the change |
| Verify | Run local checks, review independently, and fix findings |
| Explain | Publish the PR, walkthrough, evidence, and usage |
| Review | Handle GitHub review findings and required checks |
| Finish | Merge when authorized, or return the reviewed PR for your merge |

`shaka workflow` validates and prints the
[workflow definition](../skills/shaka/config/workflow.yml). The agent loads
[skill references](../skills/shaka/references/README.md) as needed.

## Trust model

Shaka exists to make the people who maintain a project faster. It trusts them:
anyone with write access, plus the users, bots, and teams you list. Their settings
and instructions on the default branch are the project's decisions, and a
maintainer can change them, such as which CI reviews a merge waits for.

Shaka's limits are for input that could try to steer the agent. On a public
repository, anyone can comment or open a PR from a fork. So the agent withholds
comments from untrusted authors, treats diffs as data rather than instructions,
and reads settings from the default branch rather than from the PR under review.
Even a comment the agent reads is review input, not an instruction: settings and
merge approval come from you and the default branch.

Other checks, such as confirming the reviewed commit before merge, catch mistakes.
They do not restrict maintainers.

## What is enforced

| Responsibility | Enforcement |
| --- | --- |
| Valid settings, command paths, and values | Ruby configuration checks |
| Which public comment bodies an agent reads | Ruby allowlist and provenance checks |
| Reviewed commit and required GitHub merge conditions | Ruby merge helper and GitHub protection |
| Posted review evidence covering the merged commit, or a stated waiver | Ruby merge helper, when the agent merges and review is required |
| Sentence, paragraph, and total length of PR descriptions and walkthroughs | Ruby publication helpers, using [`prose_limits`](settings.md#prose_limits) |
| Adequate tests, useful screenshots, and how thorough the review was | Agent judgment and review |
| Keeping private information out of publications | Agent inspection; no automated privacy scan |

The merge helper confirms that review posted on the PR covers the commit it
merges; it cannot tell whether the review was careful or its findings were fixed.
A merge you make yourself on GitHub skips this check, and so does
`review.required: none`. See [`review.required`](settings.md#reviewrequired) for
what counts as review evidence.

`shaka enforcement` lists rules enforced by code and those that rely on the agent.
Its [source map](../skills/shaka/config/enforcement.yml) describes enforcement;
it does not prove a task followed every step.

## Customize the instructions

Put commands and merge choices in [settings](settings.md). Use `AGENTS.md` for
project constraints, review criteria, and writing preferences.

To change Shaka, edit the workflow and references in a fork. Update the enforcement
map for changed rules, run the checks, and submit a PR. Install the reviewed version
explicitly; a project branch cannot replace the skill used to review itself.
