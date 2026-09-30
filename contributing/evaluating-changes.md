# Evaluate a Shaka change

Use a small, recorded experiment when tests prove a skill or plugin change works
but do not establish that it helps a maintainer. [Shaka #206](https://github.com/shakacode/shaka/issues/206)
tracks these evaluations. Record each attempt in the [experiment index](https://github.com/shakacode/shaka/blob/main/eval/README.md),
including failed harness runs. A green test, a completed PR, and an improvement in
human attention or cost are different claims.

## Set up a sandbox

ShakaCode contributors can use a team-authorized evaluation organization. Other
contributors can use their own GitHub organization or account and public test
repositories. The procedure does not depend on a particular computer, GitHub
login, or coding-agent subscription. Public repositories test public GitHub
delivery mechanics; they do not test private-organization features or hide prior
solutions from later agents.

Prepare Docker, Git, a coding agent, and a GitHub CLI. Check that the CLI inside
the **final agent image** supports the trusted Shaka helper's exact commands. Exercise
`gh pr checks --required --json name,state,bucket,link` there before a model call.
Check authenticated integration separately; a CLI help or parsing check alone
does not establish access to required checks, reviews, or Git push.

Keep two roles distinct:

- An operator creates the repository, configures protection, and grants access.
  An operator may keep a reusable credential, but it stays outside the agent
  container. Follow the [sandbox protection recipe](https://github.com/shakacode/shaka/blob/main/internal/local-evaluation-proposal.md#7-local-isolation-github-identity-and-bounded-execution).
- A non-admin agent identity gets Write only on its active test repository.
  Its credential, reusable or not, must lack Administration, Workflows, and
  check/status write permission; otherwise the hosted result is not trustworthy.
  Before each run, verify live protection has a required check and no bypass for
  the agent identity, its teams, or the Write role; `viewerCanMergeAsAdmin` must
  be false.
  In an organization, set its base repository permission to none and give it no
  team or direct grants to other private repositories. In a personal account,
  use a separate collaborator identity with no other private-repository
  grants. Verify effective access before each run. A reusable public-test
  credential is acceptable if policy permits and those limits hold. Remove its
  temporary repository grant after the run and verify removal. Do not start
  another run while an earlier grant remains. Store credentials outside source
  and logs.

Use a separate coding-agent sign-in for the sandbox if the host supports one.
Do not mount a contributor's normal agent home, SSH keys, GitHub configuration,
or Docker socket into the agent. A reusable sandbox sign-in is an operator
choice: document where it is stored and how to revoke it. It may still require
reauthorization later.

## Declare the run before spending a model turn

Record the hypothesis and decision it could change, the exact baseline and
candidate commits, one public-safe fixture, task prompt, model and effort, merge
mode, time and cost limits, and the evidence that counts as success. Pin the
fixture's seed commit tree, including files normally ignored by Git. Check that
the base passes its own validation, then require the seeded PR's intended
assertion failure both locally and in a completed hosted check at its exact head.
Run the reference repair locally first: it must pass and leave a meaningful PR
diff. A repair that restores the base byte-for-byte cannot supply a changed-file
link for Shaka's walkthrough.

Before launch, verify the container's non-root/read-only-root setup, disposable
workspace, trusted Shaka skill outside the candidate checkout, credential
isolation, permitted network egress, denied off-list destinations, and authenticated
Write access only to the target repository. Public repositories remain readable,
but even public runs must prove that private-sibling API reads and clones fail.
Private measured cells additionally require denied reads of every other private cell.
Do not relax a failed gate or substitute a model to keep the run moving. Treat a
wrong initial failure, unsupported CLI, missing access, or empty reference-repair
diff as a **harness error**, not a result for the candidate.

For an Ask delivery, grade the *current* PR head: local validation, the completed
required hosted check, an independently read-back COMMENT walkthrough bound to
that head, an open/unmerged PR, and the matching approval marker. A passing job
alone is not a successful Ask run. Stop at the declared time or cost limit and
report missing evidence as missing. Keep raw transcripts and credentials out of
public repos and PRs.

Retain public evaluation repositories and PRs as historical evidence. Add their
exact links, revisions, hypothesis, and qualified/unqualified outcome to the
[experiment index](https://github.com/shakacode/shaka/blob/main/eval/README.md) before repeating a case. Retention does
not retain temporary Write grants, run-only credentials, containers, or network
access. Verify access removal from both operator and agent views. Retain private
measured-cell repositories too, but never expose a solved cell to a later agent.
Keep a public test identity and reusable credential out of private measured cells;
use separately scoped credentials and isolated cells when the approved experiment
needs hidden evidence.

## First value case: PR #250

[PR #250](https://github.com/shakacode/shaka/pull/250) proposes loading an optional
`.agents/writing-style.md` from the trusted default-branch commit. Its tests and
CLI check demonstrate the loader mechanism, not that automatic loading improves
writing or saves maintainer effort. The cheaper comparison is an `AGENTS.md`
pointer to the same style guide. Do not merge the PR as a side effect of its
evaluation; the [experiment index](https://github.com/shakacode/shaka/blob/main/eval/README.md) records its live status.

An offline smoke check against one pinned trusted ref found no `writing_style`
field with the baseline helper and a guide with the candidate helper. That
check used no model and did not exercise a fresh consumer delivery; it does not
resolve the value question.

Pin the historical comparison to the PR's base `ceb9989d249e04b70e5d6871f384ae2ce2a89269`
and candidate `e387b5da92f979bc7571d6e3a4ed91bc8eb0e02e`, then refresh their
live status before execution. If the candidate changes, treat that as a new
revision. Current-main compatibility and merge readiness require their own
checks; a result against the historical base does not establish either.

Use a fresh consumer task that requires a PR description and walkthrough, with
the same trusted style file and task prompt in every arm. First qualify the
mechanism: baseline without an `AGENTS.md` pointer should not report the guide,
while #250 should load it from the trusted commit, not the candidate checkout.
Then test the value question against the simpler alternative: baseline **with**
an `AGENTS.md` pointer versus #250 automatic loading. Keep the model, effort,
fixture, review criteria, and delivery limits fixed; counterbalance run order
and cache conditions before making a time or token-efficiency claim. Blindly
assess whether the published writing follows the style, how many corrections a
maintainer made, and whether either arm missed delivery gates. One paired task
is a feasibility observation, not proof of broad value.

Before a model test, agree on its fixture, model, budget, and permitted repository
visibility. Record the result even if it is negative or inconclusive.
