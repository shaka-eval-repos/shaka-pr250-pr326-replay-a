# Test fleet

This is the public inventory of repositories used to exercise Shaka while it is
developed. It tracks adoption; it is not a deployment system, policy engine, or
permission to change a consumer repository.

## Versions

Three different identifiers appear in this work. They are not interchangeable:

| Name | Current value | Meaning |
| --- | --- | --- |
| Product stage | `0.0.x` | Public identity: Shaka is the early successor to `agent-workflows`, not a second generation of that pack. |
| Gem / skill version | `0.1.0.pre.1` | SemVer of the public skill and reserved RubyGem name; the published gem is only a package-name reservation and does not include the pilot seam CLI. Stay on `0.1.0.pre.N`; this is the fleet target. |
| Seam contract | `version: 1` | Integer field in `.agents/agent-workflow.yml`. It identifies the typed contract, not the product stage or gem. |

Predecessor seams have no schema version and use a different set of keys.

`shaka seam init` records the Shaka SemVer in `.agents/shaka.md`. The fleet table
records the same value so that a repository remains visible even before its migration
merges. A schema-valid file alone does not prove which Shaka release last reviewed it.

## Active fleet

| Repository | Default branch | Target Shaka | Schema | State | Evidence or next action |
| --- | --- | --- | ---: | --- | --- |
| [`shakacode/shaka`](https://github.com/shakacode/shaka) | `main` | `0.1.0.pre.1` | 1 | Source | Defines and validates the current contract; trusted base `c191a8f`. |
| [`shakacode/control-plane-flow`](https://github.com/shakacode/control-plane-flow) | `main` | `0.1.0.pre.1` | 1 | Merged | [PR #496](https://github.com/shakacode/control-plane-flow/pull/496), merge `3d16440`. |
| [`shakacode/cypress-playwright-on-rails`](https://github.com/shakacode/cypress-playwright-on-rails) | `master` | `0.1.0.pre.1` | 1 | Merged | [PR #266](https://github.com/shakacode/cypress-playwright-on-rails/pull/266), merge `0af3983`. |
| [`shakacode/react-on-rails-demo-flagship`](https://github.com/shakacode/react-on-rails-demo-flagship) | `main` | `0.1.0.pre.1` | 1 (PR) | Draft | [PR #60](https://github.com/shakacode/react-on-rails-demo-flagship/pull/60), head `4d90e4b`; hosted checks pass, but local full validation remains blocked by existing dependency-audit findings. |
| [`shakacode/react-on-rails-demo-gumroad-rsc`](https://github.com/shakacode/react-on-rails-demo-gumroad-rsc) | `main` | `0.1.0.pre.1` | 1 (PR) | Draft | [PR #131](https://github.com/shakacode/react-on-rails-demo-gumroad-rsc/pull/131), head `0dc56b5`; demo smoke and validation fail on container-image pull authorization. |
| [`shakacode/react-on-rails-demo-hacker-news-rsc`](https://github.com/shakacode/react-on-rails-demo-hacker-news-rsc) | `main` | `0.1.0.pre.1` | 1 | Merged | [PR #104](https://github.com/shakacode/react-on-rails-demo-hacker-news-rsc/pull/104), merge `280310d`. |
| [`shakacode/react-on-rails-demo-marketplace-rsc`](https://github.com/shakacode/react-on-rails-demo-marketplace-rsc) | `main` | `0.1.0.pre.1` | — | Blocked | No migration PR yet. Its QA-stress setting still has a consumer; move it to dedicated repository configuration and retain a compatible reader before converting the typed seam. |
| [`shakacode/react-on-rails-demo-ssr-hmr`](https://github.com/shakacode/react-on-rails-demo-ssr-hmr) | `master` | `0.1.0.pre.1` | 1 (PR) | Open | [PR #109](https://github.com/shakacode/react-on-rails-demo-ssr-hmr/pull/109), head `5c9dbfa`; hosted checks pass, with one open maintainer-review discussion on changing merge policy. |
| [`shakacode/react-on-rails-starter-tanstack`](https://github.com/shakacode/react-on-rails-starter-tanstack) | `main` | `0.1.0.pre.1` | 1 | Merged | [PR #234](https://github.com/shakacode/react-on-rails-starter-tanstack/pull/234), merge `c0e1226`; policy follow-up [PR #241](https://github.com/shakacode/react-on-rails-starter-tanstack/pull/241), merge `3503501`. |
| [`shakacode/react-on-rails-demos`](https://github.com/shakacode/react-on-rails-demos) | `main` | `0.1.0.pre.1` | 1 (PR) | Open | [PR #129](https://github.com/shakacode/react-on-rails-demos/pull/129), head `f11d6cc`; hosted checks pass and all review threads are resolved. |
| [`shakacode/react-ppr-from-scratch`](https://github.com/shakacode/react-ppr-from-scratch) | `main` | `0.1.0.pre.1` | 1 (PR) | Draft | [PR #9](https://github.com/shakacode/react-ppr-from-scratch/pull/9), head `a5af7e0`; `.yalc/react` is needed for setup and full validation; review comments are resolved. |
| [`shakacode/react_on_rails`](https://github.com/shakacode/react_on_rails) | `main` | `0.1.0.pre.1` | 1 | Merged | [PR #5093](https://github.com/shakacode/react_on_rails/pull/5093), merge `231820b`; [PR #5097](https://github.com/shakacode/react_on_rails/pull/5097), merge `4c7416f`, pinned trusted validation. Live merge-queue requirements still apply. |
| [`shakacode/react_on_rails-demo-octochangelog-on-rails-pro`](https://github.com/shakacode/react_on_rails-demo-octochangelog-on-rails-pro) | `main` | `0.1.0.pre.1` | 1 (PR) | Open | [PR #35](https://github.com/shakacode/react_on_rails-demo-octochangelog-on-rails-pro/pull/35), head `e2facb8`; hosted checks pass and the review thread is resolved. |
| [`shakacode/react_on_rails_rsc`](https://github.com/shakacode/react_on_rails_rsc) | `main` | `0.1.0.pre.1` | 1 | Merged | [PR #234](https://github.com/shakacode/react_on_rails_rsc/pull/234), merge `99023a0`; follow-up [PR #238](https://github.com/shakacode/react_on_rails_rsc/pull/238), head `4428b5c`, has passing checks and resolved review threads but is not yet in the required merge queue. |
| [`shakacode/shakapacker`](https://github.com/shakacode/shakapacker) | `main` | `0.1.0.pre.1` | 1 (PR) | Waiting for approval | [PR #1311](https://github.com/shakacode/shakapacker/pull/1311), head `dd041bb`; live branch rules require an independent approval, and the current trust allowlist prevents Shaka from reading review comments. |
| [`shakacode/shakaperf`](https://github.com/shakacode/shakaperf) | `main` | `0.1.0.pre.1` | 1 | Merged | [PR #233](https://github.com/shakacode/shakaperf/pull/233), merge `cd133ae`. |
| [`shakacode/react-webpack-rails-tutorial`](https://github.com/shakacode/react-webpack-rails-tutorial) | `master` | `0.1.0.pre.1` | 1 | Merged; follow-up draft | [PR #838](https://github.com/shakacode/react-webpack-rails-tutorial/pull/838), merge `2ed4233`; [PR #839](https://github.com/shakacode/react-webpack-rails-tutorial/pull/839), head `ca751d1`, passes current hosted checks and has one maintainer-review thread open. |

Add a repository here only when it is intentionally part of current Shaka testing.
Record an exact Shaka version, not `latest`, and link the adoption or upgrade PR. A
selected repository that cannot be migrated safely stays marked Blocked with the reason
and a note that no PR exists yet. Remove it when testing ends; the repository's own
history remains the durable delivery record.
Private consumers belong in the private repository catalog, not in this public file.
Exclude archived repositories from the active fleet. Before expanding the cohort,
recheck the public examples page and each candidate's GitHub archive status.

## Rollout status and selection

The current test fleet includes every non-archived public consumer in the predecessor
inventory below plus the legacy Tutorial, for 16 consumers total. The seven repositories
linked from the current React on Rails examples page and each listed repository's public,
non-archived status were rechecked on 2026-09-25. The active table records main-branch
merges separately from open or blocked PRs; `1 (PR)` means the typed seam exists only in
the linked, unmerged PR.

`shakacode/agent-workflows` remains the predecessor reference and retirement source, not a
Shaka consumer. Its retirement work remains tracked by [issue #857](https://github.com/shakacode/agent-workflows/issues/857).

For React on Rails, the current [examples page](https://reactonrails.com/examples/) links
to these public repositories, in display order:

1. [`shakacode/react-on-rails-demo-flagship`](https://github.com/shakacode/react-on-rails-demo-flagship)
2. [`shakacode/react-on-rails-demo-marketplace-rsc`](https://github.com/shakacode/react-on-rails-demo-marketplace-rsc)
3. [`shakacode/react-on-rails-demo-hacker-news-rsc`](https://github.com/shakacode/react-on-rails-demo-hacker-news-rsc)
4. [`shakacode/react_on_rails-demo-octochangelog-on-rails-pro`](https://github.com/shakacode/react_on_rails-demo-octochangelog-on-rails-pro)
5. [`shakacode/react-on-rails-demo-gumroad-rsc`](https://github.com/shakacode/react-on-rails-demo-gumroad-rsc)
6. [`shakacode/react-on-rails-starter-tanstack`](https://github.com/shakacode/react-on-rails-starter-tanstack)
7. [`shakacode/react-webpack-rails-tutorial`](https://github.com/shakacode/react-webpack-rails-tutorial), labeled the legacy tutorial.

## Public predecessor discovery inventory

This initial discovery snapshot checked default branches on 2026-09-19. All non-archived
consumer repositories listed here have since been selected for the current test fleet;
the active table above is the current source of migration and merge status. The
predecessor repository remains a retirement source rather than a consumer.

| Repository | Default branch | Migration note |
| --- | --- | --- |
| `shakacode/agent-workflows` | `main` | Preserve hosted-QA, contributor-intake, reviewer, human-attention, and trusted-action policy outside the typed seam; retire only predecessor coordination machinery. Detailed retirement lives on [agent-workflows#857](https://github.com/shakacode/agent-workflows/issues/857). |
| `shakacode/control-plane-flow` | `main` | Preserve the release-QA runbook, contributor-intake boundary, review gate, and trusted actions. |
| `shakacode/cypress-playwright-on-rails` | `master` | Add or select a setup wrapper; preserve contributor intake and the existing review gate. |
| `shakacode/react-on-rails-demo-flagship` | `main` | Confirm live protection and review policy before replacing the minimal predecessor seam. |
| `shakacode/react-on-rails-demo-hacker-news-rsc` | `main` | Preserve the review-app and current-head merge conditions documented by the repository. |
| `shakacode/react-on-rails-demo-gumroad-rsc` | `main` | Preserve the full-check and resolved-thread merge gate, advisory-reviewer rule, and explicit absence of merge authority. |
| `shakacode/react-on-rails-demo-marketplace-rsc` | `main` | Keep the large QA-stress contract and operational scripts in their dedicated configuration; the typed seam does not replace them. |
| `shakacode/react-on-rails-demo-ssr-hmr` | `master` | Preserve the full-check and resolved-thread merge gate. |
| `shakacode/react-on-rails-starter-tanstack` | `main` | Preserve the full-check and resolved-thread gate and the risk-based distinction between low-risk automation and maintainer-gated changes. |
| `shakacode/react-on-rails-demos` | `main` | Preserve Lefthook, monorepo formatting, and review-app conditions that exceed the local validation wrapper. |
| `shakacode/react-ppr-from-scratch` | `main` | Confirm live protection and review policy before replacing the minimal predecessor seam. |
| `shakacode/react_on_rails` | `main` | Preserve its merge-queue, hosted-CI routing, secret-redaction, and public-comment trust boundaries. |
| `shakacode/react_on_rails-demo-octochangelog-on-rails-pro` | `main` | Preserve the full-check and resolved-thread gate and CI parity across Ruby scanning, lint, PostgreSQL, and renderer tests. |
| `shakacode/react_on_rails_rsc` | `main` | Preserve the full-check and resolved-thread merge gate and the existing hosted-CI behavior. |
| `shakacode/shakapacker` | `main` | Preserve `merge-readiness-check` through the repository instruction and retain live approval rules. |
| `shakacode/shakaperf` | `main` | Confirm live protection and review policy before replacing the minimal predecessor seam. |

## Predecessor to typed-seam YAML map

Predecessor YAML accepted open-ended prose keys. The typed seam rejects unknown keys
and represents only the portable delivery contract. Migration therefore means deciding
where each behavior lives; it does not mean deleting every predecessor key and hoping
the defaults are equivalent.

| Predecessor setting | Typed seam destination | Migration rule |
| --- | --- | --- |
| `base_branch` | `base_branch` | Omit it when the predecessor named the live default branch; carry it forward only when the repository really bases work elsewhere. |
| Command descriptions and `.agents/bin/*` | Fixed `.agents/bin/` interface | Provide executable `.agents/bin/setup`, `.agents/bin/validate`, and `.agents/bin/test`; add `.agents/bin/validate-local` and `.agents/bin/trigger-hosted-ci` only when those optional capabilities exist. Do not repeat these paths in YAML. |
| `review_gate`, `automation_reviewers` | `review` | Translate the actual required review and ordered available reviewers. Keep richer human conditions in `AGENTS.md`. |
| `merge_submission`, `autonomous_merge`, `approval_exempt` | `merge` plus `AGENTS.md` | Choose `ask` or authorized `auto`. Shaka follows live native state: it submits an immediate squash on a queue-disabled base or enqueues the reviewed head when Merge Queue is already enabled. Repository-specific autonomous or approval-exempt paths remain outside the portable seam. |
| `recovery.workspace_path` or `recovery.publish_locations` | `wip.include_locations` | Preserve the existing boolean. It controls publication of both the checkout path and session link. |
| Branch naming and `repo_prefix` | `branches.name` | Record the real branch template. Do not carry a coordination prefix forward unless the repository still needs it. |
| Live branch rules | GitHub | Read required checks and mutation rules from GitHub. Do not copy them into the typed seam or infer them from workflow filenames. |
| `trusted_actions` | Existing security tooling or workflow review | Preserve an operational allowlist where a repository actually consumes it. Do not copy it into the typed seam as inert metadata. |
| `hosted_ci_trigger`, `ci_change_detector`, `ci_parity_environment` | `.agents/bin/validate-local`, `.agents/bin/trigger-hosted-ci`, other wrappers, and `AGENTS.md` | Keep executable routing in scripts and human decision rules in instructions. Do not reduce full validation to the fast local subset. |
| Changelog, benchmark, release-QA, hosted-QA, security-preflight, contributor-intake, secret-redaction, trusted-actor, and QA-stress settings | Existing dedicated files or `AGENTS.md` | These remain repository policy. The typed seam's narrower YAML does not retire the behavior. |
| Coordination backend, claim labels, lane limits, follow-up prefixes, and predecessor fleet controls | No typed-seam key | Retire them only when the repository no longer uses the predecessor coordination system. Do not import that system into Shaka. |

## Script differences

Shaka applies the “Scripts to Rule Them All” philosophy: every repository exposes the
same small, predictable interface, while each script adapts that interface to the
repository's own toolchain. The three required entry points are:

- `.agents/bin/setup`: prepare the checkout without inventing a new toolchain;
- `.agents/bin/validate`: run the local or CI-equivalent gate used before review.
  It runs no test or lint suites when a fail-closed classifier proves every change is a regular,
  non-executable `README.md` or `docs/**/*.md` file; ambiguous cases run the full gate,
  whitespace checks still apply, and always-on security checks remain;
- `.agents/bin/test`: run focused tests when the task supplies paths or arguments.

`.agents/bin/validate-local` is an optional faster subset.
`.agents/bin/trigger-hosted-ci` is an optional explicit hosted-CI entrance and requires
`validate-local`. Existing `build`, `docs`, `lint`, `ci-detect`, database, server, and
QA scripts may remain in `.agents/bin`; the typed seam does not expose them as top-level contract
keys. Compose them behind the standard entry points when they are part of delivery.

Prefer a small wrapper script when adapting an existing command. A wrapper can anchor
execution at the repository root, prepare the environment, compose multiple checks,
forward arguments deliberately, and replace itself with the real command using `exec`.
A symlink is acceptable when a stable, tracked executable already has exactly the
required invocation semantics and lives inside the repository. Do not use a symlink to
hide a semantic mismatch between the standard name and its target. Keep `.agents` and
`.agents/bin` as real tracked directories; only individual command entries may be symlinks.

Repository-specific script notes found during the predecessor audit:

- `react_on_rails` has seam-doctor and drift-manifest programs, `ci-detect`, and
  `shared-skill-dir`. These are predecessor management or repository tooling, not generic
  typed-seam commands. Its merge queue and hosted-CI protocol block a mechanical conversion.
- `shakapacker` has a tested `merge-readiness-check`; a migration must not leave that
  gate unreachable.
- `react-on-rails-demo-marketplace-rsc` has install, serve, seed, reset, and QA-stress
  scripts. They stay repository-owned operational tools.
- Several predecessor consumers have no `.agents/bin/setup`; each needs a truthful no-op or real
  setup wrapper before its typed seam can validate.
- The tutorial must move its full CI-equivalent run behind `.agents/bin/validate`, its
  RuboCop-only fast path behind `.agents/bin/validate-local`, and its test entry point
  behind `.agents/bin/test`. Retain existing implementation scripts behind wrappers or
  safe symlinks rather than inverting the standard interface names. Its old seam maps
  full validation to `test` and fast validation to `validate`, so a literal compatibility
  adapter cannot satisfy both contracts. During the seam PR, make both `.agents/bin/test`
  and `.agents/bin/validate` run the full suite; the old fast step becomes slower but stays
  safe. After the fixed interface is trusted, restore focused behavior to `test` and put
  the RuboCop-only path at `validate-local`.

## Migration checklist

For each selected repository:

1. Read the default-branch predecessor YAML, `AGENTS.md`, `.agents/bin/README.md`, every wrapper
   selected for the typed seam, and live GitHub protection.
2. Classify every predecessor key using the table above. Record repository-specific behavior in
   the PR; preserve it in the typed seam, `AGENTS.md`, or its dedicated config, or explain why it is
   intentionally retired.
3. Do not run `shaka seam init` over the existing seam: the initializer is for a new
   repository and refuses conflicting YAML or wrappers. Plan the conversion with
   `shaka seam migrate --root ROOT --from-ref OLD_DEFAULT_SHA`, then apply only with
   `--apply` after the report names every retained, moved, retired, and blocking field.
   The planner never infers merge authority, review policy, or missing commands. Follow
   the agent guide's
   [ordered migration](../skills/shaka/references/migration.md): keep repository-owned
   wrappers, add missing fixed scripts only when the report says they are absent, and
   retain temporary adapters at old mapped paths.
   Where old and new meanings collide, use the stricter behavior at both paths until the
   new seam is trusted.
   Record the target Shaka SemVer in `.agents/shaka.md`, the adoption PR, and this fleet
   table. Do not write `.agents/README.md`.
4. Before upgrading Shaka, use the previous trusted installation to check the candidate
   worktree with `shaka seam check --root ROOT --ref OLD_DEFAULT_SHA`. The old trusted
   mapping remains authoritative for this first PR, which is why its paths must remain
   usable. Separately use the target Shaka version with `--local` to parse the candidate's
   mapping-free YAML and validate its fixed scripts; this local check grants no authority.
   Run focused checks and full validation, then merge through normal gates.
5. Upgrade the trusted Shaka installation only after the default branch has the new seam.
   Check a clean worktree with `shaka seam check --root ROOT --ref NEW_DEFAULT_SHA`, then
   remove obsolete compatibility adapters in a follow-up PR.
6. Open each repository PR pinned to its tested head. Update this fleet table only from
   verified PR or merge evidence.
