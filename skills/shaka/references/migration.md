# Migrate repository configuration

## Upgrade the configuration layout

`seam init` writes the `.agents/shaka/` layout, and `seam migrate` still writes
`.agents/agent-workflow.yml` beside `.agents/bin/`. Both layouts work; this upgrade
moves the older one.

Ask your agent: “Upgrade this repository's Shaka configuration layout.” For a
repository already using the current version-one contract at `.agents/agent-workflow.yml`,
run the installed, trusted Shaka helper from outside the candidate checkout:

```bash
shaka seam upgrade --root /path/to/repository
```

The JSON preview lists moves, recognized script repairs, repository-local symlinks,
tracked references, and blockers. It is read-only. Review the entire preview and
resolve blockers before applying it. Copy the preview's `digest`; changed inputs
require a new preview and digest:

```bash
shaka seam upgrade --root /path/to/repository --apply --digest PREVIEW_DIGEST
```

Apply checks the inputs again, moves the contract and allowlist into `.agents/shaka/`,
and moves Shaka's standard commands into `.agents/shaka/bin/`. It leaves unrelated
`.agents/bin/` tools and the `.agents/shaka.md` pointer in place. It preserves YAML
values, script modes, and command arguments. Recognized root calculations use Git
instead of a fixed number of parent directories. Ambiguous moved commands, tracked
scripts with shebangs that refer to old paths, computed path prefixes, and directory-wide
patterns block for explicit repair. Other unambiguous tracked text references to moved
files, including CI and guide references, are rewritten. Historical changelog lines
stay as written. Historical-sounding guide lines block for explicit repair, because
a current instruction can appear later in the same line. Existing new-layout files,
including ignored private files, are never overwritten.
Old-path references inside the contract or repository allowlist block instead of
being rewritten, so their settings and comments are never silently changed.
Ignored or untracked tools at the old command location also block: they may
depend on moved siblings or become visible to Git after moving. Back up such a tool outside the checkout,
remove it, apply the upgrade, then restore it at the new path and update its ignore
rule. Review Git status before staging. The helper never moves that private file.
Tracked symlinks that resolve outside the checkout block because the target's
behavior cannot be verified as part of this migration. Repair that dependency
explicitly before applying.
The repaired wrappers require Git, a worktree, and an `env` command that supports
`-u` to clear Git environment variables at run time. If commands run from
an archive or container image without Git metadata, or Git refuses the checkout because
of ownership or repository safety settings, repair that deployment path explicitly
before applying; the preview does not prove equivalence in another execution environment.

If an interruption leaves `shaka-upgrade-journal.json` in the worktree's Git
administrative directory, the next preview
reports it and gives the recovery command:

```bash
shaka seam upgrade --root /path/to/repository --recover
```

If all files already match the completed upgrade, recovery removes the journal and
reports `completed` without moving them back. Otherwise, recovery restores only
files recorded by that operation. If one of those files has
changed since the interruption, preserve the edit and repair it manually before
retrying. A normal apply failure restores the affected files automatically. Stop
other writers before applying or recovering: the upgrade changes several files,
and its checks cannot protect an edit made by another process at the same instant.
Then run
`shaka seam check --root /path/to/repository --local`, the moved validation command,
and harmless setup and test probes relevant to the repository. Compare behavior with
the previous commands before committing. Until the migration PR merges, continue to
load trusted policy from the old default-branch commit with `--ref SHA`; the candidate
layout grants no policy or merge authority.

This command differs from `seam migrate` below: `migrate` converts an older contract
shape to the current version-one schema. `upgrade` moves an already valid version-one
layout without changing its settings.

## Migrate an older contract

Use `shaka seam migrate --root ROOT --from-ref OLD_DEFAULT_SHA` to preview a
migration. Inspect every retained, moved, retired, and blocking field before
adding `--apply`. It does not infer missing commands, review policy, or merge
authority. See the [migration checklist](https://github.com/shakacode/shaka/blob/main/internal/fleet.md#migration-checklist).

Older keys are deliberately rejected during this pilot:

| Old field or flag | Replacement |
| --- | --- |
| `review.ci_review_agents`, `review.check`, `review.github_action_check` | `review.ci_review_jobs` |
| `review.reviewers`, `review.local_reviewers` | `review.local_review_agents` |
| `--ci-review-agent`, `--review-check`, `--github-action-check` | `--ci-review-job` |
| `review.pace` | `review.ci_review_wait`; `swift` becomes `one`, `thorough` becomes `all` |
| `--pace swift` / `--pace thorough` | `--ci-review-wait one` / `--ci-review-wait all` |
| `recovery.workspace_path`, `recovery.publish_locations` | `wip.include_locations`; migration preserves the boolean value |
| `plan` | Point to the requirements document from `AGENTS.md` |
| YAML `commands` mapping | Fixed `.agents/bin/` scripts |
| `protection`, `trusted_actions`, `merge.method`, `merge.release` | Live GitHub settings, workflow files, or the repository's actual security tooling |

For the old command-path mapping, migrate in this order:

1. With the previous Shaka still installed, prepare the mapping-free YAML and fixed
   scripts. Preserve adapters at old paths. Where old and new roles conflict,
   make both run the stricter checks until the new contract is trusted.
2. Validate the candidate with the previous installation and old trusted SHA.
   Separately validate it with the target Shaka using `--local`. Both must pass
   before the migration PR merges through normal gates.
3. Upgrade Shaka, load the new default-branch SHA with `--ref`, then remove obsolete
   adapters in a follow-up PR. Optional names use hyphens: `validate-local` and
   `trigger-hosted-ci`.

A newly renamed key can also make an older installation reject trusted policy.
Coordinate the contract change with the installation upgrade, including tasks
already running when the change merges.

`version` remains `1` for pilot changes that reject old keys loudly. It becomes
`2` when an otherwise valid key changes meaning or default, or when repositories
outside the pilot depend on the contract. Unknown keys never silently take a
new meaning.


Finish by checking the new installation against the merged default-branch commit.
Report the installed revision, configuration changes, and any active tasks still
using the previous installation.

The old `swift` setting skipped CI review after a different-provider local review.
Migration uses `one` to preserve its CI backstop; choose `none` explicitly if you
want local review alone to satisfy review, regardless of provider.
