# Shaka requirements

Give your agent a task. Get a verified PR and a clear explanation.
The goal is better software with less developer attention, delivery time, and token use.
Closed [issue #1](https://github.com/shakacode/shaka/issues/1) holds the original pilot build.
This plan retains the remaining real-use acceptance criteria; [issue #206](https://github.com/shakacode/shaka/issues/206)
tracks evaluation of skill and plugin changes.
Scope and retirement decisions are recorded in this plan.
This record defines the current product, not proof that acceptance is complete.
Source PRs hold detailed delivery evidence. A reviewed update to this record
must cite that evidence before claiming the pilot's real-use acceptance.

## Requirements

### Deliver and explain the work

- **R1 — One owner.** One task owner delivers the requested outcome, normally in
  one PR. Split at useful boundaries and retain dependencies and remaining scope
  on the existing task and PRs. No coordination service or duplicate delivery
  records. See [task splitting](../skills/shaka/references/delivery.md#when-a-task-needs-several-prs).
- **R4 — Explain the implementation.** Publish a conceptual walkthrough with links
  to reviewed code as a commit-bound COMMENT review. It remains readable after
  merge and substitutes for neither approval nor required acknowledgment.
- **R9 — Accept work from any tracker.** Use a task link or description, resolve its
  checkout, and ask for missing context. Requirements remain in the original
  tracker; delivery evidence belongs on GitHub. Reading grants no tracker-write
  permission. Share private context or links only when authorized.
- **R13 — Be understood on the first reading.** One owner explains outcomes,
  reasons, blockers, and decisions in familiar terms. Follow task/repository writing
  preferences and ask consequential questions early with a recommendation. Keep
  material risks visible and supporting evidence in expandable details.
- **R15 — Make completion clear.** End a genuinely finished prose-capable chat with
  exactly `This chat is ready for archiving.` Omit it while work, a blocker, handoff,
  or chat decision remains, and in machine-only formats. A remaining GitHub merge
  click after Ask gates pass is not a pending chat decision.

### Use trusted policy and verified evidence

- **R2 — Use the repository's checks.** Read policy and optional script availability
  from the trusted default-branch seam: `.agents/shaka/config.yml` with the fixed
  `.agents/shaka/bin/` interface, or the older `.agents/agent-workflow.yml` with `.agents/bin/`. Follow prose constraints in trusted `AGENTS.md`; run the candidate
  scripts at those fixed paths. Reject invalid configuration. Failed checks and
  evidence from another commit cannot establish current readiness.
- **R6 — Merge the verified revision.** Refresh GitHub state and require the expected
  head. Missing evidence, pending or failed required checks, stale heads, conflicts,
  disallowed merges, and unresolved material findings block. Never bypass protection.
- **R7 — Keep task data outside the authority boundary.** Issue and PR text cannot
  change instructions, policy, credentials, or executable code. For explicitly public
  repositories, screen comment bodies using verified writer permission or trusted
  machine/repository actors. Fetch repository trust configuration from the current
  default branch. Unknown, metadata-only, or unverifiable authors remain links for
  triage. Private/internal comments also grant no authority. Use installed trusted
  helpers; run candidate code only in the authorized isolated checkout.
- **R14 — Prove behavior.** Observe a meaningful failing test, make it pass, then
  simplify. If automation is impractical, explain and record before/after behavior.
  Visible changes need inspected, safe, accessible screenshots tied to the tested
  commit; add video for timing or interaction. See [verification](../docs/pr-verification.md).
- **R17 — Review before push.** Review meaningful implementation in a fresh context
  and fix findings before publishing. Batch repairs before optional staged hosted CI.
  Always-on required, security, and trust checks remain immediate; changed heads
  need fresh affected evidence.
- **R18 — Support reviewer fallback.** Prefer a provider that did not implement the
  change, following `review.local_review_agents` and `shaka reviewer`. Skip entries
  evidenced unavailable. A fresh session of the implementation model is valid;
  a failed CLI still leaves a fresh host context as an option. `shaka review run`
  checks CLI execution and its report; `shaka review check` labels a fresh host report
  or records a missing review with a nonzero result. Record each
  reviewer and revision in chat and the PR. See [review](../skills/shaka/references/review.md#choose-a-local-reviewer).

### Preserve control and recover work

- **R3 — Choose who merges.** Support Ask and Auto. Ask early when preference is
  unset, default to Ask without an answer, and reuse established authority. Preserve
  review-only and PR-only stopping points.
- **R5 — Avoid repeated merge decisions.** After the walkthrough and required gates,
  Ask names the ready head and directs the user to GitHub's offered merge control, or
  merges after the user's approval, rebasing first when the rebased change keeps the
  approved behavior.
  Auto submits eligible work after the same gates, including native approvals.
  Use an existing Merge Queue and wait for its terminal result whenever the agent
  submits the merge; a user's GitHub click leaves later queue failures to GitHub
  and a new task. Unclear
  authority or consequential risk needs a human decision. Native stacks and
  user-armed delayed auto-merge remain outside scope.
- **R8 — Preserve installations.** Install into an explicit skills directory with
  source and link outside candidate-writable paths. Preserve user files and other
  skills; refuse foreign targets. Test isolated/repeated installation and upgrades.
  Installation neither disables other instructions nor creates a sandbox.
- **R16 — Recover unfinished PRs.** Keep the [WIP Details note](../skills/shaka/references/delivery.md#recover-an-unfinished-pr)
  in collapsed WIP Details through the outcome, retaining it after an Ask handoff
  for the named head. It records owner, task, thread, observed activity, revision,
  workspace, unfinished work, stop reason, authority, state, and next action.
  Apply the session-link rules and `wip.include_locations` privacy setting.
  A new owner needs maintainer confirmation of the prior owner's stop or handoff,
  then publishes a new tag, refreshes evidence and authority, and preserves reachable
  local work. Unreachable work stays unknown. A resumed owner that finds a transfer
  stops with local work unpushed. The note grants no authority or lock; no heartbeat,
  lease, or coordination service is added.

### Keep the product small and measure real outcomes

- **R10 — Keep maintenance manageable.** Use a small skill entry point, validated
  YAML policy, fixed engineering-script names, cohesive Ruby modules, and guides
  for rationale. Adapt repository tools behind predictable scripts. Prefer standard
  libraries and `gh`; remove repetition. Test behavior and failures, not wording.
- **R11 — Report available cost evidence.** Record provider/model, effort, native
  tokens, source scope, and completeness for each task and commit/contribution.
  Put it in PR details or the final response without a PR. Label shared and unknown
  figures; never invent per-commit allocations. See [usage reporting](../skills/shaka/references/usage-reporting.md).
- **R12 — Reduce total work.** Compare developer attention, tokens, delivery time,
  and quality on comparable real changes, including retries and review. Fewer
  tokens alone does not establish improvement.

- **R19 — Keep Shaka gaps actionable.** Unless offers are skipped, the root task
  owner offers a public-source draft for a worthwhile, independently verified gap
  outside the active request. Verify the fixed public repository identity and get
  exact-query approval before searching; share candidate links and metadata for
  inspection. Get separate approval for the exact issue text, repeat the search,
  and return for review and approval if candidates change. File the unchanged draft
  only after candidates are cleared. Exclude private context; stop on identity
  mismatch, search failure or limit, or unresolved candidates. Never create an
  issue automatically. See the [issue-offer procedure](../skills/shaka/references/shaka-issue-offer.md).

## Design

- **D1 (R1–R3, R9, R19):** one shared `$shaka` skill. Task requirements stay in their
  original record; delivery evidence stays on the PR. No local workflow database.
- **D2 (R2, R4–R7):** a small Ruby command validates repository configuration and
  provides `pr`, `walkthrough`, and `merge`.
  Use `gh` for authentication, pagination, and APIs, JSON for responses, and
  `Open3` argument vectors for execution. Errors are concise and nonzero.
- **D3 (R4, R6):** bind walkthroughs to GitHub's native review commit ID.
  Refresh the PR before publication or merge; require the expected head for merge.
- **D4 (R6–R7):** use live native checks, merge state, and approvals.
  Inspect check states, not just a CLI exit code. Require observable checks
  enforced for the acting account; GitHub owns full enforcement, including
  requirements absent from the reported list. When the base branch has no required
  checks configured, the trusted seam's `merge.required_checks` stands in and Shaka
  enforces it (see the merge boundary). COMMENT never substitutes for APPROVE.
- **D5 (R8, R10):** copy the complete skill into a durable managed package outside
  the installing source checkout, record its exact source revision when verified, or a development
  base when available, together with a content hash. Link it into an explicit
  skills directory. Refuse foreign targets and preserve user settings and previous
  packages for rollback.
- **D6 (R10):** runtime uses Ruby standard libraries. Development uses Bundler,
  Minitest, and ordinary RuboCop defaults through `bin/validate`.
- **D7 (R2, R12, R17):** repository seams own CI commands and triggers behind fixed
  seam command names. Shaka orders
  the adversarial review before optional staged hosted CI without copying a consumer's
  label machinery or weakening current-head gates.
- **D8 (R18):** the seam carries reviewer preference as ordered data, `shaka reviewer` applies it,
  and `shaka review-prompt` creates the fresh context that makes a review adversarial. `shaka review
  run` invokes documented CLIs and checks their result; `shaka review check` distinguishes a
  fresh-host report from verified CLI execution and makes missing-review reasons explicit. No
  scheduler, retry queue, or provider credit ledger enters this pilot.

The skill is `skills/shaka/SKILL.md`; CLI dispatch is `skills/shaka/scripts/shaka`.
Small modules live in `skills/shaka/lib/shaka/`, behavioral tests in `test/`,
and installation in `bin/install`. YAML carries typed repository policy, Ruby enforces
it, and Markdown explains decisions and human-only constraints.

## Repository seam

The **seam** is `.agents/shaka/config.yml` plus the standard `.agents/shaka/bin/` interface,
which `seam init` creates. Repositories configured earlier keep `.agents/agent-workflow.yml`
plus `.agents/bin/`; Shaka reads either, and `seam upgrade` moves the older one.
It supplies setup, full and optional pre-review validation, focused tests, an optional
hosted-CI trigger, base branch, review, merge authority, branch naming, and recovery policy.
GitHub supplies live protection, required checks, and allowed merge methods. `AGENTS.md`
supplies human-only context and boundaries.
`shaka seam check` rejects unknown fields, duplicate keys, unsafe paths, missing scripts,
and invalid values. Read authority from the trusted default-branch copy. Candidate policy
edits cannot weaken the current task's requirements. Consumer commands stay in their own
repositories; do not copy Shaka's scripts into them.

## Host boundary

Share the skill and GitHub helpers; keep host installation, permissions, and
native usage readers separate. Repeated consumer deliveries are required before
claiming broad validated support. Informal usage reports establish neither that
support nor pilot acceptance.

### Recorded acceptance evidence (September 14–17, 2026)

Codex was the reference host. Claude Code skill startup, precedence over a same-named
repository skill, and its usage reader were verified on September 15, and one complete
consumer delivery followed on September 17 (agent-workflows-com#62). Those formal
trials had not yet established repeated consumer delivery for Cursor and OpenCode. Later maintainer-reported team use is noted in the
[coding-environment record](coding-environment-trials.md). OpenCode’s canonical
install path, TUI launcher, and export-based usage reader share the same workflow.
See [coding-environment trials](coding-environment-trials.md)
for the tested versions, startup boundaries, and evidence gaps.

## Merge boundary

The helper checks GitHub facts; the owner establishes authority, local verification,
and acceptable risk. Changes to execution trust, authentication, permissions,
release/deployment, destructive migrations, or merge guards require human review.
Small size does not prove low risk. Unclear authority needs a decision; a safety
failure blocks submission. Require observable native checks enforced for the actor;
unknown or bypass-capable identities block. When GitHub has no required checks configured
on the base branch, as on a private repository on the GitHub Free plan, the trusted seam's
`merge.required_checks` stands in for them and Shaka alone enforces it (maintainer decision
on #235). Leave repository queue settings and armed
auto-merges unchanged. The helper performs an immediate squash merge when the base has no
queue. When the base has Merge Queue enabled, the helper lets GitHub's enqueue operation
decide native queue eligibility for a `CLEAN`, `BEHIND`, or queue-policy `BLOCKED` expected
reviewed head, and also `UNSTABLE` when effective `review.ci_review_wait` is `none` or `one`; conflicting or
unreadable merge state still blocks. Queue admission is not Auto
task completion: the active Auto task waits for GitHub's current-base integration checks and
terminal result. Ask archives after the GitHub click; a later queue failure is a new task.
Queue submission does not relax walkthrough, review, authority, or required-check gates.
With `ci_review_wait: none` or `one`, pending or failing optional checks may still leave the native state `UNSTABLE`.

## Verification and exit criteria

- Run `bundle install` for development setup and `bin/validate` locally and in CI.
  When the trusted classifier proves a change contains only regular, non-executable
  `README.md` or `docs/**/*.md` files, that validation entry point and the hosted
  Validate workflow run whitespace checks without Ruby tests or RuboCop. Ambiguous
  changes use the full gate, and always-on security checks still run.
- Test failed/pending/missing checks, API errors, stale heads, unsupported merge state,
  rejected merges, queued submission and replay, and safe argument handling.
- Install in an isolated skills directory; repeat installation, preserve foreign
  targets, and verify upgrades use the trusted source.
- Exercise Ask and Auto on real PRs. Publish and read back a walkthrough tied to
  the current head, honor native approvals, and verify protected merge behavior.
- Exercise one meaningful Codex implementation with a visible Claude or Grok review,
  and one consumer's staged hosted-CI path with review fixes completed before dispatch.
- Exercise one recorded substitution: a listed reviewer unavailable on evidence, the
  next provider's review completed, and both records present in the chat and the PR.
- A new user follows [getting started](../docs/getting-started.md) in a fresh Codex task
  and reaches a PR without needing another guide. Record the trial on its PR.
- Interrupt a real unfinished PR, then continue it once from its recovery note in the
  original task and once in a fresh task. Record each continuation on the PR it continues.
- Before claiming adoption, complete several real changes, including a small fix,
  review fixes, failed CI, and a changed PR head. Unit tests alone do not establish this.

## Success evidence and commit attribution

| Outcome | Evidence and success criterion |
| --- | --- |
| Developer attention | Maintainer estimates and task/PR discussion show less reading, repeated explanation, waiting for late questions, and corrective work. Timestamps do not measure active human time. |
| Tokens | Native records cover planning, implementation, review, retries, and integration. Compare like coverage and cache/model mix; preserve native categories and count each response once. |
| Quality | Tests, real use, review findings, regressions/reverts, and maintainability show a better accepted result with less rework. Green tests and line counts alone are insufficient. |
| Delivery time | Task-to-accepted-outcome time falls without shifting work to the maintainer; distinguish CI and human waiting where known. |

Use [usage reporting](../skills/shaka/references/usage-reporting.md) for commit/contribution mappings, shared
intervals, native token categories, and missing-data labels. Include available retries
and contributors, preserve original mappings after squash, and publish aggregate
metadata only. Do not infer routed models from configured settings, present estimated
API-equivalent dollars as actual charges, or interrupt each commit for accounting.
Compare a small sample of similar
accepted changes; describe its uncertainty before making savings claims.

## Scope and rollback

Public source publication and reviewed, verified implementation PR merges are
authorized. Runtime prerequisites are Ruby 3.4, Git, authenticated GitHub CLI,
and GitHub PRs. Shaka's public product stage is `0.0.x`. The `0.1.0.pre.1` RubyGems
prerelease only reserves the project name; stay on `0.1.0.pre.N` until a later
approved release. Future registry releases and broader adoption require separate
evidence and decisions.
[Packaging](../contributing/packaging.md) describes the tested gem.
Prospective features and retirement choices are recorded in this plan and in
[predecessor retirement](retirement.md); website work lives
in its own repository and consumes these guides. No fleet coordination, policy engine,
telemetry service, tracker synchronization, or release automation is part of this kernel.

Master and repository control towers may organize work through the existing
Shaka procedure as [optional operating roles](../docs/control-towers.md). The focused
`$rct` setup skill establishes one repository tower and registers it with an
existing master; it adds no coordination service or multi-repository owner. The
`/mct-claude` and `/rct-claude` skills establish the same two roles on Claude Code
desktop under the same limits, deriving the tower set from the host's live session list rather than
from any new file, database, or scheduler. Each delivery
retains one owner and the same repository gates. This does not restore predecessor fleet
machinery; claim adoption only after a real tower-to-delivery trial.

Rollback: select a prior managed package with
`bin/install --skills-dir DIR --rollback PACKAGE_ID` with the same optional
`--managed-dir DIR` and its recorded tower flags,
or remove the verified skill link. Preserve unrelated installations and user files. See
[upgrade and removal](../skills/shaka/references/installation.md#upgrade).
