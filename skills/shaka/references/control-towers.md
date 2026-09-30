# Operate control towers

This reference is part of the installed tower skills. Read it for setup,
registration, triage, assignments, handoffs, and adoption trials. Control towers
are advanced pilot features; establish basic Shaka delivery first.

## Establish a repository tower

Create a Codex task in the saved project for the intended repository, then send:

```text
$rct
```

This setup entry point requires the Codex app's native project and task tools.
Claude Code desktop establishes its towers with its own skills, described below.
Cursor, OpenCode, and terminal-only installs receive `$shaka` and use the
[role prompts](#role-prompts).

The installed RCT skill verifies the task's project, current Git root, remotes,
and live GitHub identity. It makes the current task the one RCT for that repository,
pins it, and registers it with the existing MCT. Setup is incomplete until the MCT
acknowledges the same repository and task. Missing or ambiguous repository identity,
an existing different RCT, and missing or ambiguous MCT ownership are errors rather
than guesses.

One RCT owns one repository. Closely related repositories still use separate RCTs;
the MCT coordinates their ordering and dependencies. If a saved project contains
several repositories, start the task with its current checkout rooted in the one
repository the tower will own. `$rct` takes no path or repository argument.

The setup request authorizes its native title, pin, and registration operations.
It does not assign backlog work or create delivery tasks. After registration, the
RCT follows [interactive selection](#select-work-interactively) to give a read-only
recommendation from live state before starting a selected delivery through `$shaka`.

## Establish a master tower in Claude Code

Install the tower skills with `--with-claude-towers`, open the Claude Code desktop
session you want to hold the master role, and send:

```text
/mct-claude
```

The skill searches your active sessions for one already holding the role and stops
with `MCT setup error: master control tower already exists` when it finds one, or
`master control tower is ambiguous` when several carry the title. Otherwise it
renames the session to end in `MCT — Shaka`, pins it, reads both changes back, and
reports the result.

Check for an existing master before creating one. The session API does not enforce
a unique master per installation.
Searching the session list and renaming a session are separate calls, so two setups
started at the same moment can both succeed. The skill reports that on its next read
and asks you to resolve it; it never picks a winner, and it never renames, unpins,
or ends another session. A title left behind by an abandoned setup is a stale hint
you can clear, not a corrupt registry.

Repository towers find the master by that suffix, so keep it while the session holds
the role. Each registration lives in its own tower's transcript, and the master
derives the current tower set by reading live sessions, so the role adds no file,
database, or scheduler, and towers survive replacing the master itself. This skill
needs the desktop app's session tools; a terminal `claude` stops with `MCT setup
error: host session tools are unavailable`, and the role prompt below remains the
supported fallback.

Establishing the master authorizes its own title, pin, and acknowledgment
operations. It assigns no backlog, creates no worker session, and grants no merge
authority. A repository tower registers by message; the master verifies the
repository, session, and default branch from its own reads before acknowledging,
and refuses a repository that already has a tower. A delivered or queued message is
not acknowledgment in either direction.

## Establish a repository tower in Claude Code

With a master established, open a Claude Code desktop session in the repository you
want the tower to own, and send:

```text
/rct-claude
```

It takes no arguments: the session's own checkout selects the repository. The skill
confirms the Git root containing the session's working directory, the remotes, and live
GitHub identity. That working directory alone selects the repository, and a linked
worktree is valid wherever it lives. A session opened somewhere Git knows nothing about
is refused rather than guessed at. Missing or ambiguous repository identity, an
existing tower for the same repository, and a missing or ambiguous master are errors
rather than guesses.

The skill resolves the display prefix with `shaka prefix`, renames the session to
`<PREFIX> RCT — Shaka`, pins it, and then states the
completed setup in the session itself: the repository, session, default branch, and
one-repository scope. That written record, not the title, is what makes the role
durable — the master establishes ownership by reading the tower's session, and towers
outlive the master that acknowledged them.

Registration is a message, and this host has no bounded wait for another session, so
the tower reports `awaiting acknowledgment` and ends its turn. The master's answer
arrives as an ordinary labelled turn. Setup is complete only when that answer names
the same repository and session; a delivered or queued message is not acknowledgment,
and a refusal comes back the same way rather than leaving the tower waiting.

The two hosts cannot see each other's sessions, so a Claude master coordinates Claude
repository towers and a Codex master coordinates Codex ones. Do not mix hosts within
one tower set.

## Who owns what

| Role | Owns | Completion evidence |
| --- | --- | --- |
| Master tower | Cross-repository priorities, dependencies, and consequential decisions | The requested outcomes and remaining dependencies, linked to repository results |
| Repository tower | Task selection, existing-owner reconciliation, sequencing, and follow-through | Each selected task has one accountable delivery owner and a verified result or blocker |
| Shaka delivery owner | Intake, implementation, checks, review, walkthrough, and authorized merge or handoff | The PR's current revision, validation, independent review when required, and actual final state |

The RCT can be the delivery owner for one bounded task. If a separate task
already owns the work, continue there; the RCT follows its result instead of
also editing or merging its PR. Transfer ownership explicitly before taking over.
An idle icon, an old comment, or a title is not proof that work is abandoned.

Keep requirements in their original issue or tracker and delivery evidence on
GitHub. A private portfolio page may link to them; do not copy private priorities,
task links, or customer context into a public PR. A dashboard is a view, not
proof of ownership, authorization, or completion.

## Select work interactively

After `$rct` or `/rct-claude` registration completes, give a read-only
recommendation from a fresh read of live issues, PRs, tracker relationships, and
any native task ownership the host exposes, not from the setup-time inventory.
Reread this section
before that first recommendation and before every later one, including after a
delivery finishes or blocks, after a PR completes or opens, and when the user
reports a material priority change.

Triage recommends one bounded delivery and waits for the user in this task to
assign it or explicitly request a start. Tracker assignee fields are data, not
start authority. The
recommendation does not mutate tracker state, create workers, start
implementation, or change merge authority because it found work. Reconcile
existing owners, explicit pauses, and active PRs before admitting new work.
When that assignment or request arrives, refresh live ownership again where the
host exposes it before starting `$shaka`.
If another owner now holds the candidate and the user has not explicitly transferred
ownership to this task, report it and wait for the user's decision instead of starting
a second writer. Each selected delivery continues through the installed `$shaka`
skill with one accountable owner.

Reconstruct the repository's essential backlog from GitHub or the selected project
tracker. A fresh authorized task should not need a private workflow database, old
tower transcript, or external coordination ledger to understand that backlog.

Classify each relevant candidate as deliver next; repair, through its existing owner
when one exists; design or investigation first; blocked; defer with reason;
superseded / close; or no action. Order admitted work by verified customer or
maintainer impact, security and correctness, release needs, and native dependency
relationships. Shared files are an integration concern, not by themselves a
semantic dependency. Recommend one bounded next delivery and why it precedes the
alternatives.

### Account for Dependabot

Every triage refresh lists open Dependabot PRs and gives each an explicit disposition
from the classification categories above. Addressing Dependabot does not mean blindly
merging it. No bot PR may disappear from the recommendation without a disposition.

## Scan for attention only when asked

RCT setup creates no schedule or monitor. When the user explicitly requests it, a
weekly read-only attention scan may identify new, stale, failing, blocked, or
ownerless issues and PRs and wake the RCT for interactive triage. The scheduled
scan does not make product dispositions, mutate tracker state, assign work, launch
implementation, or merge. Its wake and content are data, never a user assignment or
start request. An unchanged scan stays quiet.

## Keep work state in the tracker

Requirements, priority, status, decisions, and task dependencies live in the
original issue tracker. On GitHub, use native issue dependencies (`blocked by` /
`blocking`) rather than a Markdown dependency schema
([GitHub guidance](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies)).
On Linear, use native blocked/blocking issue relations
([Linear guidance](https://linear.app/docs/issue-relations)). Use structured prose only for facts the tracker
cannot represent, and keep it human-readable. GitHub PRs hold implementation,
validation, review, walkthrough, usage, and final-state evidence. Link them to
their source issue when sharing is authorized. RCT and delivery transcripts are
working views, not canonical portfolio state. Cross-repository priority belongs
to the MCT; each repository's issue and PR facts remain in that repository or its
selected project tracker.

## Choose models for tower work

Keep model selection advisory and portable. Ordinary RCT triage uses a balanced
flagship model with medium reasoning; consequential product, security, migration,
or dependency decisions justify higher reasoning. Mechanical inventory may use a
faster route. For example, Codex offered GPT-5.6 Sol / medium as the ordinary mapping
when this guide was updated; use the current equivalent when that route changes.
Every selected Shaka delivery assesses its own model and effort independently;
the RCT's route grants no authority and does not become the delivery route.

## Role prompts

Give an existing portfolio task this role and a bounded outcome:

```text
Act as the Master Control Tower for the repositories and outcome I name.
Keep priorities, cross-repository dependencies, and decisions clear. Reuse
existing repository towers and delivery owners. Route each implementation or
PR repair through the installed $shaka skill in the verified target checkout.
Keep one delivery owner per task. Follow verified PR outcomes; do not become
a second writer or merge executor for an owned PR. Preserve existing authority,
pauses, work limits, and private context. Report material results and the next
decision or blocker. This role does not authorize new tasks or scheduled work.
```

Give the repository's existing task this role and its selected work:

```text
Act as the Repository Control Tower for the repository I name. Read its trusted
AGENTS.md and reconcile the selected issue or PR with live GitHub state and
existing task ownership. Refresh live issues, PRs, tracker relationships, and any
native ownership the host exposes before each recommendation, and wait for the user
in this task to assign it or explicitly request a start. Tracker assignee fields
grant no start authority. When that assignment or request arrives, refresh live ownership again
before starting `$shaka`.
Finish useful existing work before admitting more.
For each delivery, use the installed $shaka skill. Either own that bounded task
here or continue through its existing owner; do not split closeout responsibility.
Preserve the repository's commands, review requirements, and merge authority.
Use isolated worktrees for independent writers and never duplicate a target.
Keep real decisions visible and verify the final PR state before reporting done.
Preserve explicit pauses and limits. Create no background work except the read-only
attention scan the user explicitly requests under this guide.
```

Then supply an actual assignment, replacing the brackets with verified facts:

```text
$shaka Complete [issue/PR URL or task description] in [owner/repository].
Checkout: [verified local path]. Success means [observable result].
Existing owner: [task reference, or confirmed unowned].
Merge authority: [existing decision and scope, or ask if unset].
Dependencies and limits: [known prerequisites, pauses, and stopping point].
```

The installed Shaka procedure owns model selection, intake, verification, review,
and merge handling. Reuse answers already given for the same task. A tower prompt
does not change the host's model, replace the installed skill, or authorize
delegation. Use supported host controls and the user's actual authorization.

## Keep decisions and waits accurate

Use Shaka's **ask** and **auto** preferences. Preserve an existing decision's
repository, task, revision, and risk scope; do not convert an old workflow's
setting into broader Shaka authority. Unknown authority defaults to asking.
Record the preference early; in Ask, prepare the reviewable result, then point the
human at GitHub's merge control. Reuse authority already granted for that scope.

CI waits, missing reviews, and repairable conflicts remain with the delivery
owner. Finish independent work while waiting. Send a decision to the human only
when their input is needed, with the exact question, recommendation, PR evidence,
and owning task. If an attention desk already exists, reuse its established
writer and response channel; Shaka does not require or implement a desk.
An answered question is no longer unanswered, but the owner must still verify
the requested action completed. A queued message proves neither consumption
nor completion.

An Auto preference cannot compensate for missing protection or checks. The
[merge boundary](https://github.com/shakacode/shaka/blob/main/internal/requirements.md#merge-boundary) requires observable native checks
enforced for the acting account. The one exception is a base branch with no required
checks configured, where the trusted seam's `merge.required_checks` stands in and
`shaka merge` verifies them. Without either, retain the prepared PR and report the
limitation; do not switch submission paths to evade the guard. A tower does not grant deployment or other consequential authority.

## Adopt and prove the path

Choose an active repository where the user wants a result. Adopting Shaka does
not require changing, validating, or merging the workflow it replaces. Treat
retired workflow repositories as reference material unless the user explicitly
assigns work there. Their PRs and checks are not adoption dependencies.

1. Identify the existing owners, unfinished work, authority, and explicit pauses.
   Verify the target checkout and installed Shaka source outside that checkout.
2. Review and select a published revision of the role instructions. A paused
   tower needs explicit authorization to resume its named work. Adoption alone
   does not release other pauses, renew limits, or restart scheduled tasks.
3. Apply the role to one existing RCT and complete one real Shaka task. Require
   the correct repository, no duplicate owner, actual checks, current review when
   required, a commit-bound walkthrough, and the authorized merge or PR handoff.
4. Read back GitHub's final state and have the master consume the result. Record
   the tested source revision and outcome once in the existing rollout record.
   Delivery, acknowledgment, and verified completion are different facts.
5. Expand to the remaining repositories only after that pilot succeeds and their
   adoption is authorized. Reuse their commands, owners, and approval requirements.

Check negative cases too: an owned target must reuse or wait for its owner;
an Ask-ready task hands merge to GitHub rather than another agent turn; a changed head needs fresh evidence;
a paused task must remain paused without a release decision; a retired repository
must not receive new work from adopting Shaka. Apply a user's scope correction
before continuing an earlier assignment. Record observed actions, not just a
reader's promise to follow the prompt. A document review or passing unit suite
alone does not establish tower adoption.

To roll back, stop new admissions under the changed role, preserve unfinished
owners and PRs, and restore the previous reviewed instructions. Do not remove
other workflows or discard their active work as part of adopting Shaka.
