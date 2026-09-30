# Configure a repository for Shaka

## Try Shaka privately in one clone

When the trusted default branch has no Shaka seam, inspect the repository's existing
commands and CI, then generate local settings with the installed helper:

```bash
shaka seam private setup --root /path/to/repository --ref DEFAULT_BRANCH_SHA \
  --setup-command 'bin/setup' --test-command 'bin/test' \
  --validate-command 'bin/validate' --review-policy none
```

Replace the example commands with executable commands found in that repository.
Supply `--ci-review-job NAME` with a matching review policy when a real CI review
job exists. If the repository defers hosted CI, supply
`--validate-local-command COMMAND` and `--trigger-hosted-ci-command COMMAND`
together. The private generator reuses the normal new-layout wrappers and records
Ask because a local `merge.preference` cannot establish merge authority. An explicit
task instruction may authorize Auto separately. Private setup cannot set fallback
required checks because they require a trusted source. The agent must verify
that `--ref` is the current default-branch commit; Ruby only checks that it is a
full commit SHA. Private settings do not grant trusted policy,
public-comment trust, or merge authority.

Setup prepares a copy under the clone's common Git directory, adds the anchored
`/.agents/shaka/` exclusion to its `info/exclude`, then writes the worktree's
`.agents/shaka/` files. Run `shaka seam private inspect --root DIR` when resuming
work or after outside Git updates; it captures edits to a complete private tree and reports tracked
team adoption before replacing any recovery copy. `shaka seam private list --root DIR`
lists copies even after a linked worktree is deleted. To compare one, run
`shaka seam private restore --root DIR --id ID --to /outside/inspection/path`.
Restore refuses destinations inside any Git worktree, so it is only for comparison.
A `previous` copy
is also available with `--previous`. If an interrupted rotation leaves no `current`,
default restore uses `previous` and reports that source. Each worktree gets an assigned local identity;
re-creating a deleted worktree at the same path starts a new copy without replacing
the old one.

If setup is denied or interrupted, the error names the failed path. Inspect the
copy and retry setup with the same options after fixing access; a matching partial
installation resumes. Changed options leave a differing prepared copy, so setup
refuses to replace it. Compare that copy and move it to a safe location before
starting fresh with corrected options.
After `git clean -fdx`, setup refuses to replace a recovery copy that differs
from the generated defaults. Run `private inspect` after editing private files
and before cleaning: edits made since the last inspection cannot be recovered
once clean deletes them. Restore the copy to an outside inspection path, compare it, then
copy the chosen files back into `.agents/shaka/` only when no tracked team settings
exist. Run `private inspect` again and continue with the recovered seam. To start
fresh instead, move the old common-Git recovery directory to a safe location
before rerunning setup; that deliberate move removes it from `private list`.
The clone-wide exclusion can hide newly added team files after adoption. Inspect
all linked worktrees, stage intended team files with `git add -f` while the rule
is active, and remove the exact
`/.agents/shaka/` rule from the common `info/exclude` once none still uses private
settings. Keep any other exclusion lines.
The common Git directory is the recovery boundary: deleting it loses the copies.
Direct edits overwritten by an outside Git update before `inspect` sees them may
also be lost. An ignored private destination blocks the existing `seam upgrade`
layout migration; compare it with the recovery copy before adopting team settings.
If a required wrapper is missing, or an optional pair is incomplete during setup,
`private inspect` reports `partial` and leaves the last complete recovery copy
untouched. Compare and save any new edits separately before `git clean -fdx`;
restore a complete tree before inspection can capture edits again. After setup
completes, removing both optional wrappers is a supported private choice.

## Publish team configuration

Use this procedure when asked to set up Shaka in a repository. The
[configuration reference](https://github.com/shakacode/shaka/blob/main/docs/settings.md) defines every setting
and standard script; keep those definitions there.

1. Verify the repository identity, visibility, default branch, and any existing `AGENTS.md`.
2. Inspect existing setup, test, validation, and CI commands. Reuse them in small
   `.agents/shaka/bin/` wrappers; include any existing fast validation or staged CI
   capability when useful. Shaka's own [scripts](https://github.com/shakacode/shaka/tree/main/.agents/bin) are examples
   in the older `.agents/bin/` location.
3. Establish review jobs from their actual workflows and merge authority from
   the user's instructions. Keep Ask when no broader authority exists. Check whether
   GitHub requires checks on the base branch: count `required_status_checks` rules
   with `gh api "repos/OWNER/REPO/rules/branches/BRANCH" --jq '[.[] | select(.type ==
   "required_status_checks")] | length'`, and read classic branch protection under
   **Settings → Branches** or the PR's `baseRef.refUpdateRule`. When GitHub requires
   none, or the rules API returns 403 `Upgrade to GitHub Pro or make this repository
   public` (a private repository on GitHub Free), do not stop. Offer the names
   `gh pr checks` reports on a recent PR, recommend the one that runs the full
   validation, and pass each one the user confirms as `--required-check`. Take names
   from that output, not from job names inside a CI config: CircleCI, for example,
   reports one check per workflow. Explain that Shaka, not GitHub, then enforces them.
   If the user wants no required checks, continue with merge preference `ask` and
   say that Auto merge needs at least one.
4. Prepare the files with the trusted installed helper. `seam init` creates
   version-one configuration in `.agents/shaka/`. When the repository already has
   `.agents/agent-workflow.yml`, `seam init` refuses and names the
   [layout upgrade procedure](migration.md#upgrade-the-configuration-layout); that
   configuration keeps working without the upgrade.
   For an older contract shape, use the [migration procedure](migration.md#migrate-an-older-contract).
5. Inspect the generated diff, run its checks, and commit it. When the default
   branch has no seam yet, follow [the first setup PR](#review-and-merge-the-first-setup-pr)
   path to review it before publishing and hand it to the maintainer. A migration
   keeps the normal workflow gates. Merge before relying on the new policy.

For a repository whose commands and review job match this example, the initializer
is:

```bash
"$HOME/.agents/skills/shaka/scripts/shaka" seam init \
  --root /path/to/repository \
  --setup-command "bin/setup" \
  --test-command "bundle exec rake test" \
  --validate-command "bin/validate" \
  --review-policy meaningful_changes \
  --ci-review-job claude-review
```

Use the helper under the skills directory passed to `bin/install`; this example
uses `~/.agents/skills`. Replace every example command with the repository's
actual command. If no CI review job exists, use `--review-policy none` and omit
`--ci-review-job`. Meaningful
implementation still gets local review. The initializer refuses to overwrite
conflicting files. When GitHub enforces no required checks, add
`--required-check NAME` for each confirmed check.


## Review and merge the first setup PR

When the default branch has no Shaka configuration, every `--ref` command stops
with `Cannot find .agents/agent-workflow.yml or .agents/shaka/config.yml`. That includes
`seam check`, `reviewer`, and `merge`. The refusal is correct: the setup PR must not
grant itself review or merge policy. Do not work around it with the candidate's
own YAML. Handle that one PR this way:

1. Validate with `shaka seam check --root . --local` and the new wrapper scripts.
   The local check proves syntax only.
2. Choose the local reviewer by hand with the
   [usual selection rules](review.md#choose-a-local-reviewer), treating the
   reviewers `shaka review run` supports as the list, in this order:
   `anthropic/claude`, `openai/codex`, `xai/grok`. The same-provider and
   fresh-session fallbacks still apply. `shaka review run` needs no seam.
3. Fix its findings, then push and open the setup PR against the default branch,
   since later `--ref` reads come from there. Record in the PR that no
   trusted seam existed, so the reviewer came from this fixed order rather than
   from `shaka reviewer`.
4. Without a trusted `review.ci_review_wait`, wait for the required checks and for
   each configured CI review job that runs on the PR. Read findings only through
   `shaka comments`; the default branch may not trust that CI reviewer yet, so
   name any withheld CI review for the maintainer instead of reading it another
   way. Advisory bots stay advisory.
5. Do not run `shaka merge`, and do not merge with `gh pr merge`. Once checks and
   review pass, name the head SHA and hand the PR to the maintainer. The setup adds
   executable wrappers and merge policy, so ask them to review those files before
   they merge it on GitHub under the repository's existing protection.

After that merge, each later task resolves the current default-branch commit at
intake and passes it as `--ref`.


## What `seam init` writes

Supply `--root`, `--setup-command`, `--test-command`, `--validate-command`, and
`--review-policy`. Unless review policy is `none`, supply `--ci-review-job` for
an actual job; repeat it for additional jobs. Supply `--required-check` for each
check the user confirms when GitHub requires none; see
[`merge.required_checks`](https://github.com/shakacode/shaka/blob/main/docs/settings.md#mergerequired_checks). With no
required checks at all, keep merge preference `ask`.

The initializer writes `.agents/shaka/config.yml`, the three required wrappers in
`.agents/shaka/bin/`, and the `.agents/shaka.md` pointer. The YAML holds `version`,
`review`, `merge`, the default `branches.name`, and `wip.include_locations: true`.
Each wrapper finds the repository root with Git, so it runs the same from any
directory and from a linked worktree; `--root` must therefore be the Git worktree
root. The initializer refuses Shaka command names left in `.agents/bin/` without
their configuration, leaves other `.agents/bin/` tools alone, and checks write
access before writing anything. It defaults to Ask. Add `--merge-preference auto`
only with established authority, `--base-branch` for another base, and
`--required-check` for seam-declared checks. Add optional reviewer entries and
`repo_prefix` by editing the YAML afterward. Set `wip.include_locations` to
`false` only when the user asks to hide the checkout path and session link.
If the repository already uses `AGENTS.md`, it may point to its requirements
there; Shaka does not require that file.

Command arguments are parsed as argument lists. Put pipelines and other compound
shell behavior in repository scripts rather than in command flags.


## Validate the configuration

While editing, check the current checkout:

```bash
shaka seam check --root . --local
```

For a task's trusted policy, resolve the repository's default branch to an
immutable commit and use that SHA:

```text
shaka seam check --root . --ref FULL_DEFAULT_BRANCH_SHA
```

A PR's proposed policy cannot grant that PR new authority. `--ref` reads policy
and optional script availability from the trusted commit, then validates the
scripts in the candidate checkout. Inspect changes to those scripts before
executing them. `--local` grants no policy or merge authority; omitting both
flags performs the same candidate check with a warning. Combining them is an error.

The JSON output includes derived `commands` and `validation` fields. They describe
the result; do not copy them into the YAML. Even trusted output reports
`grants_merge_authority: false`: the agent still establishes authority and checks
live GitHub state.
