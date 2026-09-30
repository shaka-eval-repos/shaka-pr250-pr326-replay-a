# Working with Shaka

## Give it an outcome

Describe the result or provide an issue or task link. Include constraints the
agent could not infer:

```text
$shaka Add CSV export to the orders page. Reuse the filters shown on screen.
```

Shaka checks for existing work and recommends a model and effort level. Say
“Go” to start without restating them when the recommended settings are already
active. You can name a model or effort you prefer; Shaka pauses if it differs
from the recommendation or cannot verify the active settings. See the
[workflow](workflow.md).

## Choose a merge policy

| Policy | What happens |
| --- | --- |
| **Ask** (default) | Review the ready PR, then merge it on GitHub or approve it so the agent merges. |
| **Auto** | The agent merges after required checks, review, and approvals. |

Set the choice in your prompt: `Use merge policy ask` or `Use merge policy auto`.
Repository restrictions and required approvals still apply. Trust, authentication,
release, and other consequential changes need explicit human review. Put additional
project restrictions in `AGENTS.md`. A PR past the
[size limits](settings.md#mergelimits) goes back to you before the agent merges it.

You can also request planning only, review only, or a PR without merging.

## Find PRs waiting on you

The agent labels a PR when it stops for you:

| Label | What it waits for |
| --- | --- |
| `awaiting-answer` | Your answer. A description with decisions lists the questions |
| `awaiting-merge-approval` | Your merge or approval of the named commit; set only under **Ask** |
| `awaiting-resume` | You to resume the agent; it paused with nothing set to wake it |

You don't create these labels. The first time the agent needs one in a repository,
it creates it: `awaiting-answer` in amber, `awaiting-merge-approval` in purple, and
`awaiting-resume` in blue, each with a description. Recolor or reword them freely; the agent never changes a
label that already exists. Creating a label needs write access; with triage access
the agent can still apply labels someone else created.

A description that includes those questions applies `awaiting-answer` and removes
`awaiting-resume`. It refuses to publish them while `awaiting-merge-approval` is set.
An empty decisions list removes that section and `awaiting-answer`, and leaves the other
two labels in place.

To approve, tell the agent in chat. An **Approve** review on GitHub also counts
when it comes from a login you named to the agent as a merge approver; GitHub does
not let the account that opened the PR approve it. Return to the chat so the agent
can act on the approval. If GitHub requires updating the branch first, the agent
rebases, revalidates, and merges without asking again. When a branch rule requires
GitHub approval of the new commit, it asks for that approval. When the rebase changes
behavior, with or without conflicts, it explains the difference and asks you to
approve the new commit. While it waits for either approval, the PR keeps its
`awaiting-merge-approval` label.

A PR carries at most one of these labels. The agent removes it when work resumes.
Search `is:open label:awaiting-answer`, `is:open label:awaiting-merge-approval`, or
`is:open label:awaiting-resume` to see your queue. Nothing but the agent clears these labels, so one can go stale
if the agent stops before work resumes; remove it by hand.

To resume an `awaiting-resume` PR, or any PR whose chat was lost to a crash or restart,
paste the **Next action** from its WIP Details into a new chat, such as
`$shaka https://github.com/OWNER/REPO/pull/N` in Codex. The agent runs `shaka handoff`
first to read the PR's live state, then continues.

## Squash with a useful commit message

When a PR is ready for your merge, the agent posts the squash commit message as the
PR's last comment, just above the merge button: a title such as `Add CSV export (#42)`
and a short plain-text body that says what changed and why, followed by the branch
commits' `Co-authored-by` lines. Each block has a copy button; paste them into
GitHub's squash merge boxes. When the head changes, the agent posts a new comment
and deletes the old one. When the agent merges under **Auto**, it sends the same
message itself, except through a merge queue, which uses the repository default.

GitHub fills those boxes from a repository setting, by default with every branch
commit's title. To start from the PR title and an empty body instead, set **Settings →
General → Pull Requests → Allow squash merging** to **Default to pull request title**.

## What you get

The agent reproduces bugs, tests new behavior, runs your checks, and handles
independent review findings before pushing.

The PR shows the result and verification. Screenshots show UI changes; a code
walkthrough explains implementation choices. Expandable sections hold usage
estimates, detailed checks, and **WIP Details** for unfinished work.
See [PR verification](pr-verification.md).

The agent handles routine choices and asks about decisions affecting the product,
scope, or risk.

## Give feedback

### On GitHub or in chat

Leave PR comments, then paste the review link into the agent chat and ask it to
address them. Or give feedback directly in chat: describe what feels wrong or show
what you want.

### In your editor

Put rough edits or voice-dictated notes beside the passage that needs attention.
An optional `Agent:` prefix distinguishes notes from finished wording.

1. Tell the agent you are editing and to keep the checkout read-only.
2. Leave your notes unstaged. Local edits and commits do not trigger GitHub CI;
   pushing to an open PR normally does.
3. Stop editing and hand over the files.
4. The agent backs up your notes outside the repository, applies the feedback,
   and validates the finished changes before pushing.
5. Resume editing when the agent hands the checkout back.

Take turns writing to the same checkout. With separate worktrees, hand over a
final diff for the agent to reconcile. Keep raw notes in the local backup.

## Resume unfinished work

Open the PR's **WIP Details** to find the owning chat, last known state, and next
action. The **Thread** link can reopen the conversation when the owner's machine
is reachable. In Codex, `codex://threads/...` takes you back to the original chat
to pick up where the agent stopped. Before another agent takes over, confirm the previous one has
stopped or handed off; a timestamp cannot prove it.

## Split a large change

Ask for independently useful changes as separate PRs. For example, a React on
Rails upgrade may need React 19: merge the React update first, then finish the
integration.

Each PR gets its own tests and review. The agent updates the remaining branch
after each prerequisite merges. The original chat owns the overall outcome;
no stacked-PR service is needed.

## Suggest improvements to Shaka

Tell your agent in chat what you would like Shaka to do better. For example:
“Shaka asks too many setup questions—can we simplify that?”

The agent helps refine the idea and asks before filing an issue.
