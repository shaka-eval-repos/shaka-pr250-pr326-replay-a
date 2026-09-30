# Predecessor retirement

Shaka is the early `0.0.x` successor to [`shakacode/agent-workflows`](https://github.com/shakacode/agent-workflows).
Execute the legacy-repository work on
[agent-workflows#857](https://github.com/shakacode/agent-workflows/issues/857);
keep detailed backlog disposition there. This page is the Shaka-owned checklist
and the portable-behavior gate before a legacy component is removed.

Do not port predecessor coordination, fleet, receipts, or the policy engine.
Do not archive `agent-workflows` before named consumers have a verified Shaka path.

## Freeze and exceptions

- Freeze new product features in `agent-workflows` now.
- Accept only bounded security fixes, correctness fixes needed to finish a
  migration, and retirement or documentation changes.
- Do not port new Shaka behavior back into the predecessor, and do not require
  parity with retired machinery.

## Consumer order

The migration pause is lifted for the 16 public consumers selected in the
[current Shaka test fleet](fleet.md#rollout-status-and-selection). Work from the
active-fleet statuses and blockers; do not start migrations outside that cohort
until the maintainer expands it. The named consumers below retain their original
retirement-checklist work:

- [React on Rails](https://github.com/shakacode/react_on_rails) — [PR 5093](https://github.com/shakacode/react_on_rails/pull/5093); point the seam at Shaka and mark leftover predecessor files transitional.
- [Control Plane Flow](https://github.com/shakacode/control-plane-flow) — migration completed by [PR #496](https://github.com/shakacode/control-plane-flow/pull/496), merge `3d16440`; same rule.

Record pinned revision, consumed files, whether each behavior moves to Shaka,
stays repository-local, or is retired, and the owning migration PR. Private
repository names stay out of this public file.

## Messaging

- New adopters follow [getting started](../docs/getting-started.md) and never need
  `agent-workflows`.
- Predecessor README and install paths must say Shaka is the successor and that
  a legacy seam is transitional.
- Open predecessor PRs and issues get an explicit disposition on #857; do not
  close them as completed work.

## Archive criteria

Archive `agent-workflows` only after the maintainer explicitly chooses that
action and all of these hold:

- Shaka getting-started does not require the predecessor repository.
- Named active consumers validate through Shaka.
- Remaining predecessor files in those consumers are marked transitional or gone.
- Open predecessor issues and PRs have a recorded disposition.
- Durable docs or redirects needed by merged consumer history remain readable.

## Portable behavior before removal

Remove a predecessor component only when Shaka already covers the portable
need, or the consumer has a repository-local replacement, or the behavior is
intentionally retired. Minimum Shaka coverage before dropping a legacy install
or seam-doctor path:

- trusted source install and host recipes in getting-started;
- typed seam `version: 1` with fixed `.agents/bin/` commands;
- `shaka seam check --ref` against the default branch.
