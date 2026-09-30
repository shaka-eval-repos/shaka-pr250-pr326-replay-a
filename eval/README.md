# Evaluation experiments

Use the [contributor guide](../contributing/evaluating-changes.md) to set up and
grade a run. This index prevents a harness failure from being mistaken for a
successful skill evaluation or repeated without a changed hypothesis.

| Experiment | Evidence | Outcome |
| --- | --- | --- |
| Slice 0 main/Ask r4 | [#206](https://github.com/shakacode/shaka/issues/206); repository deleted before the retention decision | Harness failure. The repaired PR passed checks, but the final image's GitHub CLI could not execute the trusted required-check query. No COMMENT walkthrough or Ask marker. |
| Slice 0 main/Ask r5 | [retained repository](https://github.com/shaka-eval-repos/shaka-slice0-ask-feasibility-206-r5), [PR #1](https://github.com/shaka-eval-repos/shaka-slice0-ask-feasibility-206-r5/pull/1) at `7820fab178704b7a9cea88d480b7542bc753e40d` | Harness failure. The intended initial assertion failed locally and in hosted CI; the repair passed both, but restored the base exactly. With zero changed files, the trusted walkthrough could not publish. PR remains open and unmerged; no Ask marker. |
| Writing-style loader [PR #250](https://github.com/shakacode/shaka/pull/250) | Proposed first value case; pinned comparison in the [guide](../contributing/evaluating-changes.md#first-value-case-pr-250) | Offline CLI smoke: the baseline helper at `ceb9989` omitted `writing_style`, while the candidate helper at `e387b5d` returned a 903-byte guide from that trusted ref. This proves the output-path difference, not agent behavior or value over an `AGENTS.md` pointer. No model comparison has run; PR is on hold. |

Retain evaluation repositories and PRs for history, keeping private measured cells
inaccessible to later agents. Remove temporary access after each run. Before a
new experiment, compare its hypothesis, fixture, baseline and candidate commits,
model/effort, prompt, and success gates with
this index. Public solved repos are not hidden test cells.
