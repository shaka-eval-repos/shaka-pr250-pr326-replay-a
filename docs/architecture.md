# Why Shaka stays small

Shaka carries one task to its requested outcome: usually a reviewed pull
request, sometimes a plan or review only. One agent task owns delivery through
review, merge, or handoff.

Shaka uses the work item and GitHub as its shared record, avoiding a separate
tracking system.

## Keep facts where people look for them

- When there is a work item, it holds the reason for the work: priority, scope,
  and dependencies. For tasks started from a description, capture that context
  in the PR.
- GitHub holds delivery evidence: commits, checks, reviews, and the PR outcome.
- The agent task holds experiments and unpushed work. That context is temporary.

A fresh PR reader should be able to reconstruct the owner, blocker,
revision, and next step from the work item and GitHub. An unfinished PR carries a
short [recovery note](working-with-shaka.md#resume-unfinished-work) for that
purpose. The note helps someone continue the work.

## Put repeatable checks in code

Ruby handles configuration validation, comment filtering, and merge checks. Skill
instructions guide the agent’s decisions. This keeps repeatable checks testable
and reduces the instructions the agent must interpret.
