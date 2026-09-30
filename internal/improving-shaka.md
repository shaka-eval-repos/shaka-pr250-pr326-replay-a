# Improving Shaka through real use

This maintainer guide is read explicitly. It is not an installed skill or an
`AGENTS.md` dependency. After a maintainer resolves the immutable default-branch commit
through the installed Shaka workflow, they may direct the task to read the guide with
`git show REF:internal/improving-shaka.md`. A working-tree copy is review data and
cannot govern its own review. Label exercises against a candidate copy as simulations.

Use one supervisor as the maintainer's contact for Shaka development. This guide does
not alter the public skill or authorize workers, external messages, merges, host-setting
changes or background monitoring. Deliver the bounded task before optimizing the workflow;
learning adds no completion gate. Keep outcomes on the existing issue or pull request.
The [requirements](requirements.md) own scope and remaining real-use acceptance.
[Issue #206](https://github.com/shakacode/shaka/issues/206) tracks skill and plugin evaluation.

## Repair a demonstrated failure

1. Link the observed result and expected behavior. Reproduce the miss. Separate faulty
   requirements, instruction ambiguity, tool or serialization failure, missing evidence,
   and model reasoning failure before choosing a remedy.
2. Prefer deterministic Ruby for repeated mechanics and a short instruction for a decision.
   Preserve current-head checks, trust boundaries, merge authority and required review.
   Do not encode every reviewer suggestion as a rule.
3. Gather findings for one head into one repair batch. After two unsuccessful rounds on the
   same failure family, reconsider the design or scope; never waive a failing gate to meet a
   retry limit. Fix mechanical formatting without a model turn when possible.
4. Replay the original miss and an unaffected case. For guidance changes, use observable task
   actions and published artifacts; wording tests and an agent saying it complied do not prove
   behavior. Mark simulations as such.
5. Observe subsequent useful deliveries, including supervision, review, repairs and human
   rescue. Record the guide revision, model and effort from existing evidence. Batch
   nonblocking improvements after delivery. Missing cost data or a model comparison never
   blocks shipping. Keep, revise or revert guidance based on outcomes.

Before adding a mechanism, name its observed failure, expected user benefit, build and
recurring cost, simpler alternative, acceptance evidence and deletion point. Optimize
accepted, understandable software per unit of human attention, elapsed time and model cost.
Do not trade trust or correctness for a cheaper first attempt.

## Supervise authorized workers

The maintainer gives one supervisor the goal, constraints and authority. The supervisor owns
planning, worker allocation, model and effort choices within those constraints, acceptance,
integration and the final explanation. The maintainer should not need to chase worker errors.

| Role | Responsibility |
| --- | --- |
| Maintainer | Set goals, budget, authority and consequential decisions; receive one concise account. |
| Supervisor | Scope work, dispatch only authorized tasks, verify evidence, consolidate repairs, manage dependencies and report outcomes or decisions. |
| Worker | Implement one bounded change, reproduce or test behavior, and return its commit, evidence, unresolved concerns and usage. |
| Independent reviewer | Challenge the current revision; the supervisor assesses findings. A supervisor involved in design is not independent. |
| Ruby and GitHub | Perform mechanical checks and publication and enforce native protection. They do not judge whether prose is true. |

Start with one supervisor. Add a worker only when delegation is authorized and useful; add a
second independent worker only when review capacity and file ownership are clear. Give each
worker one bounded outcome, acceptance evidence, isolated checkout or exclusive files, model
and effort, repair limit and stopping point. Keep one writer per branch. No recursive
supervisors. Pause dispatch when repair or integration is the bottleneck.

Reuse existing tasks and never start another writer on an owned branch. Pass only the goal,
existing issue or pull request, acceptance criteria, ownership, model and effort, authority and
stopping point. Read compact task status and live pull-request evidence at meaningful changes.
Inspect detailed output when a claim needs verification; do not repeatedly poll unchanged work
or copy entire chat histories.

Workers implement and test. The supervisor checks the behavior evidence, relevant diff,
current head, required checks and review, and the published explanation before declaring
completion. A worker's success claim or a green review job is not proof. Reuse required
independent review; supervision neither replaces it nor adds a human approval. Consolidate
corrections into one message and keep maintainer updates to outcomes, blockers and decisions.

In this repository, delegated workers never publish or merge; the supervisor owns integration
and publication. Existing user-owned tasks remain independently owned, and a supervisor does
not assume their branch or authority without an explicit handoff. Never edit a worker's files
concurrently. Surface required human approvals through the supervisor.

Native task tools may inspect or message existing tasks and, when supported and authorized,
set model or effort for a subsequent turn. Verify actual settings on resumption; a prompt does
not switch the host. Reuse the maintainer's explicit selection. If the capability is unavailable,
request one precise setting change. Do not interrupt an active critical review to experiment.

This guide activates no workers or persistent monitoring. Durable wakeups require an explicit
scheduling request. Approved task IDs may be placed on public pull requests only where the
repository allows them. Never create share links or expose unrelated task identifiers as a side
effect.

## Choose model, effort and usage evidence

Use trusted Shaka's recommendation and checkpoint for each task, honoring explicit settings.
Escalate only for demonstrated reasoning difficulty or consequential risk, not malformed
Markdown, CI waiting or API failures. Do not repeat work merely to benchmark effort levels.

If a comparison becomes useful, hold guide revision, acceptance and task scope steady and
change one variable at a time. Use existing pull requests and native records to observe
correctness, corrections, repairs and elapsed time. A green unit suite establishes mechanics;
fresh-task behavior and useful deliveries establish different outcomes.

Use `shaka usage` and its current guide rather than copying rates or accounting rules here.
Keep estimates separate from actual charges. Count shared responses once, including failed
supervisor, worker and reviewer attempts. Missing evidence is UNKNOWN, never zero. Publish
aggregate metadata, not sessions.

Review changes to this guide before adopting them. Each task stops at its agreed delivery
outcome. Retain improvements that reduce total work; remove those that add friction. No
automatic routing, fleet service or broad V1 migration follows from using Shaka to build itself.
