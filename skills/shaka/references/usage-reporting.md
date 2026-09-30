# Model, token, and cost reporting

Report available usage for each task's commits and contributions:

```text
shaka usage --commit FULL_COMMIT_SHA --contribution implementation --format json
```

`--format json` prints `note`, `columns`, and `record`. Markdown stays the default.
Put each report's `record`, which includes its `columns` and its `note`, into the description
`usage.records` list, and one report's `note` into `usage.note`. The table is built
from those records, so everything it shows can be carried by a later publish. A
`details` item whose summary names usage is refused.

The description renders one table with a row per report label. Reports with the
same host, label, provider, configured and routed model, and effort, such as eight
review runs of one model, share a row marked `×8`; rows that share only a label also
show their host, model, and effort. With more than one row, a total row adds the USD
and credit estimates; it leaves token counts blank, because hosts count input
differently. The collapsed summary shows the USD total. Columns are USD, Codex
credits, Input, Cached input, Output, Reasoning, and Cache writes; a column no report
measured is left out, and a collapsed glossary under the table defines each column
shown. Report names keep their hyphens from breaking the line. Dollar amounts are
rounded to cents, and token counts are shortened to about three figures, such as
45.3M; the hidden record keeps the exact counts. A
cell no report measured shows `—`, and `+` marks a minimum: a partial estimate, or a
sum that left out an unmeasured report. The total can count a response twice when two
kept reports partly overlap.

Reports from before this table are listed below it and left out of the total, which
then shows `+`. Each record is also kept as a hidden block holding its reported
columns and note. A later publish that carries the block puts its row back in
the table.

Each report is priced once, when `shaka usage` runs, with the rate card installed then.
A carried report keeps that price; nothing reprices it. A collapsed **How each report
was measured and priced** list under the table shows each report's note: its rate card,
the date its prices were verified, and what its sources left out. A PR left open across
a price change therefore shows which rows used which prices. To price every row with current rates, rerun `shaka usage` for each report and
publish the new records.

Put that `usage` object in the PR, or the JSON report in the final response when
there is no PR. **Native** figures come from the host's records. **Estimated** figures apply a
rate card to those records. `UNKNOWN` means the records do not establish a value;
it never means zero.

## Select the work being reported

The helper supports Codex, Claude Code, Cursor, OpenCode, and Pi. It normally
selects the latest turn. That is a snapshot, not necessarily the whole task.

| Option | Use |
| --- | --- |
| `--host NAME` | Select a host when multiple host markers are present |
| `--file PATH` | Read a saved native source; repeat for additional sources |
| `--turn ID` | Select specific turns; repeat as needed. Each host section below names the ID field |
| `--all-turns` | Include a session dedicated entirely to this task; cannot combine with `--turn` |
| `--since-time UTC` | Include responses at or after the task began in a shared session; whole-second sources include the start second. Cannot combine with `--turn` or `--all-turns` |
| `--commit SHA,SHA` | Associate the selected interval with several commits |
| `--contribution CATEGORY` | `implementation`, `review`, `integration`, or `shared-planning` |

Record the UTC start time before the new task begins. Use explicit `--turn` IDs
when that time is unavailable or the boundary must be exact, and mark an uncertain
interval SHARED.
The start time and native response timestamps may use `Z` or a numeric timezone offset; the report presents their interval in UTC.
The command fails if a response has no usable timestamp with a timezone, or if any native source is incomplete. A failed export, unreadable record, or missing response identity could undercount the selected interval.
It also fails when the start time selects no responses or any selected source record is aggregate usage.
For sources recording only whole seconds, it includes the full cutoff second so responses from the new task are not lost. That boundary can include an earlier response from the same second; treat its attribution as shared.

A `--turn` ID that matches no readable response fails with the expected field
instead of printing an empty table. A source with no readable responses still
reports them as unavailable.

Use explicit host selection for a child agent launched inside Pi, which inherits
Pi's process marker. Selecting Pi never falls back to unrelated Codex records.

Report local review from the **reviewer's** source with `--contribution review`.
Include available retry and contributor records. Hosted reviewers and tool-model
calls remain `UNKNOWN` when their records are absent.

An interval associated with several commits is **SHARED**. Never divide its tokens
into invented per-commit amounts. Preserve the original mapping after squash and
associate the merged SHA without recounting it.

The helper deduplicates response IDs across supplied files, including resumed or
forked copies, and ignores cumulative snapshots. Conflicting counters,
configuration, or interval metadata produce `UNKNOWN`.

## Keep earlier reports when work changes hands

Pass each JSON `record` through in `usage.records`. When `description` republishes
a PR, it keeps earlier reports unless a newer record covers the same work, so a
handoff between hosts or models keeps every contribution. The kept text is the
earlier marked report: a record's row rejoins the table, and a report from before
the table existed stays below it. A report that read no source gives way to a
complete report from the same host that measured the same contribution and commits.
Fork PRs never carry reports.
The command prints how many reports it retained, replaced, and dropped. A newer
report that kept only some counters can still replace an earlier report.

## Reading the result

The Markdown report records commits, contribution, observed interval, source
version, provider/model/effort, and token categories. Its metric rows have one column
per configuration. Configured and routed models remain distinct.

| Host | Input and cache categories | Other limits |
| --- | --- | --- |
| Codex | Input includes cache reads; cached input must not be added again. Cache writes have their own field. | Reasoning is part of output. Routed model is unknown. |
| Claude Code | Input excludes cache reads and writes; all three are separate amounts. | Reasoning is part of output. Configured model and native total are unknown. |
| Cursor | Input includes cache reads and writes; rows show the subsets. | Reasoning, native total, and parent-chat subagent usage are unknown or absent. |
| OpenCode | Input excludes cache reads and writes. | Native total sums input, output, reasoning, cache reads, and cache writes. |
| Pi | Input excludes cache reads and writes. | Native total is copied. Reasoning, when recorded, is part of output. |

Reports are **PARTIAL** while sources omit active work, reviewers, subagents, or
tool-model usage. They do not establish actual charges or human active time.
Missing usage does not block an otherwise authorized PR or merge.

## What the Codex reader includes

The reader finds one matching session under `CODEX_HOME` (default `~/.codex`)
using the exposed thread ID, then verifies session metadata. It does not search
unrelated transcripts or use a parent's session. Inherited host context means the
source may be shared; it does not prove which agent produced every response.

Each supplied file contributes its latest turn by default. The reader reports
configured provider/model/effort, token categories, cache writes, and native total.
The tested records do not establish the routed model.

Validation used desktop `0.154.0-alpha.6.2` and CLI `0.154.0` records. A fresh CLI
trial matched 14 responses to an independent aggregate; supplying the source twice
did not change the result.

## What the Claude Code reader includes

`CLAUDE_CODE_SESSION_ID` selects a transcript under `CLAUDE_CONFIG_DIR` (default
`~/.claude`). The reader checks its ID and includes subagent transcripts from the
selected turn. A turn is the `promptId` on a `type: "user"` record, not that
record's `uuid`. List them in order with
`jq -r 'select(.type == "user") | .promptId' FILE | uniq`. Multiple supplied files use
the first file's latest turn by default. Streamed copies count once, using the final
usage line.

For CLI reviews, save `claude -p --output-format json` output. The reader consumes
the result object's `usage`, never its review text, and its turn is the `session_id`. An `is_error` result is unknown.
A present top-level `model` is used; otherwise a single `modelUsage` entry can supply
`canonicalModel`. Multiple model entries leave the route unknown. Effort is reported
only when recorded.

Transcript responses report the routed model and recorded effort. Validation used
desktop `2.1.270` and CLI `2.1.272`: an independent aggregate matched a session with
a subagent, and two CLI runs matched the host's totals. The transcript format is
internal and version-dependent; unreadable records produce `UNKNOWN`.

## What the Cursor reader includes

`CURSOR_CONVERSATION_ID` selects one JSONL file under `CURSOR_USAGE_DIR` (default
`~/.cursor/shaka-usage`). Install the [stop hook](installation.md#cursor) to
persist allowlisted usage fields. Transcripts and bubble `tokenCount` values are
unused because tested Grok sessions stored zero there despite hook-reported usage.

A turn is a `generation_id`; the default is each file's latest generation.
`stop` and `afterAgentResponse` events for one generation count as one response.
The installed hook saves `stop` events. Parent events exclude subagents; a local
review in another conversation needs its own report.

Validation used desktop `3.20.21` / `grok-4.6` and `3.21.16` / `grok-4.7` payloads.
The reader accepts `reasoning_effort` when `effort` is absent. The `context`
parameter is not a price.

Without records, the report says `usage reader unavailable: no readable Cursor
stop-hook records`. Host context may still supply provider `cursor` and model or
effort from `CURSOR_MODEL_ID`, `CURSOR_MODEL`, and `CURSOR_MODEL_EFFORT`. Explicit
file or turn selection does not borrow the current chat's model environment.

Doctor fails when the stop hook is absent from `~/.cursor/hooks.json`. A missing
file for the current conversation only degrades, as expected before its first stop.

## What the OpenCode reader includes

Name a session with `--host opencode --session ses_ID`; find it with
`opencode session list`. The reader also accepts `OPENCODE_SESSION_ID` from a
wrapper or plugin, or saved exports through repeated `--file` options.

The reader runs `opencode export` and keeps per-message metadata, never message
parts containing transcript text. OpenCode 1.18.31 truncates piped JSON, so export
is redirected to a temporary file before parsing.

A turn is a user message. Assistant messages join it through `parentID`. The
default selects the latest user turn; `--all-turns` includes responses with
identified turns. Rows use the export's provider, session model as configured
model, response model as routed model, and response variant as effort.

A 49-response session from 1.18.31 matched an independent aggregate for response
count, all five token categories, total, interval, and version. Missing configured
models and unreadable records stay unknown.

## What the Pi reader includes

`PI_SESSION_FILE` must point to a v3 session whose nonempty header ID matches
`PI_SESSION_ID`. Missing, ephemeral, older, malformed, or mismatched evidence
produces `UNKNOWN`. Saved evidence can use `--host pi --file PATH`; legacy sessions
need reopening or export with current Pi.

The reader validates entry IDs and parent links, then walks from the active leaf
to the root. Abandoned branches are excluded. A turn is a user message and the
following assistant responses before the next user message. Multiple files default
to the first file's latest active-branch turn. `--turn` selects active-branch user
entries; `--all-turns` includes all identified turns on that branch.

Rows use each response's selected provider/model, optional `responseModel` as the
route, and active-branch thinking-level entries as effort. Missing reasoning stays
unknown unless zero output proves zero reasoning. Invalid reasoning or reasoning
greater than output makes that response's usage contradictory.

Pi's `usage.cost.total` supplies **native nominal cost**; Shaka does not recalculate
it. Validation against Pi 0.85.1 matched independent active-branch aggregates for
tokens and cost. Malformed trees and conflicting copies produce `UNKNOWN`.

The reader excludes compaction, branch-summary, and tool-nested model usage and
discloses excluded summarizer usage on the active branch. A dedicated session's
`/session` total may be separate comparison evidence; do not edit it into the
helper report or attribute summary usage to a turn.

## Cost estimates

The helper prices supported responses individually before summing. This handles
model switches and context thresholds without charging cached input twice.
Effort has no price multiplier. Unsupported models, missing counters, and
contradictory records leave that response unpriced. The column then sums the
priced responses and marks the estimate `(partial)`, naming how many responses
were left out and why; it is `UNKNOWN` only when no response could be priced.

Implementation estimates read `skills/shaka/config/model-rates.yml` from the
git checkout of the current directory, including a command started in a
subdirectory of that checkout. Pass `--rate-root DIR` to name a different
checkout. Review estimates and every other contribution keep the installed card,
including when that option is set. The installed command still applies its own
pricing formulas. The report names the card it used. The verified date is the
date written in that card, so an implementation estimate can show a date supplied
by the candidate checkout. A card the installed loader cannot check fails the
report.

| Scenario | Treatment |
| --- | --- |
| Standard Codex credits | Configured supported OpenAI model. A response with cache writes is unpriced because their credit rate is unpublished. |
| Standard API-equivalent USD | Ordinary input excludes cache reads and writes, which use their own published rates. |
| Cursor on-demand USD | Configured supported Grok model and recorded Fast/standard mode. Cache writes remain ordinary input because no separate rate is published. |
| Anthropic list-price USD | Supported routed model first, otherwise supported configured model; standard speed and published Opus fast mode are priced. |
| Pi native nominal USD | Copy the host's recorded cost instead of applying a rate card. |

Rate notes and source links apply only to supported provider/model pairs. A
supported model with missing counters still gets the rate note and an explanation
of its unknown estimate. The table's model is the one actually priced.

### Anthropic details

Input, cache reads, and writes are separate. Use the recorded 5-minute/1-hour
`cache_creation` split; an unsplit write total stays unknown. Fast mode is priced
at twice standard token rates for Opus 5.5, Opus 5, and Opus 4.8; cache multipliers
stack on top. Fast mode for other models and unrecorded speed stay unknown. Standard
and fast responses remain separate columns.

Add the recorded web-search charge. An absent server-tool group or search counter
means no searches; a present malformed group or invalid count is unknown. Fetch
adds no separate charge. Server-side code execution is excluded because per-response
records do not establish container-time cost or monthly allowance treatment.

Recorded US-only inference applies 1.1 times token rates, excluding the per-request
search charge. Absent US routing uses the provider's global default. The September
23, 2026 rate record has no Anthropic long-context multiplier.

### Cursor and OpenCode details

The September 21, 2026 Cursor rate record covers Grok 4.6 and 4.7, including Fast
variants. Grok 4.7 above 256k reported input uses twice standard rates, or three
times Fast rates. Grok 4.6 has no long-context multiplier. Missing billing mode
leaves the estimate unknown. Cursor-only reports omit Codex credits.

OpenCode's cache-exclusive input does not match the OpenAI/Cursor estimator's
required input shape, so those scenarios remain unknown. Its Anthropic responses
also remain unpriced because exports lack billing speed.

These are dated rate-card scenarios, not invoices. Subscription treatment,
discounts, service tier, routing, account terms, and actual charges may differ.

## Publish the report

Publish through the description `usage` object described at the top of this guide.
Keep the coverage note visible; do not replace unknown reviewer usage with zero.

Check task coverage before publishing. Sources can contain unrelated work even
when a launcher began with a single task. Select relevant turns rather than using
`--all-turns` in that case. The reader prints aggregate metadata only and does not
modify sessions or publish to GitHub.

Never publish raw sessions, prompts, tool output, source paths, or turn/response
IDs. Recovery-note session links follow their separate [publication rule](delivery.md#recover-an-unfinished-pr).

## PR execution provenance

The required `provenance` object records task source and requested, recommended,
and active model/effort. `task_source` is `description`, `issue`, or `pull_request`;
missing route metadata is `UNKNOWN`. The initial prompt is excluded. The renderer
adds the public alias from `SHAKA_MACHINE_ALIAS`, or `UNKNOWN`; it never falls back
to a hostname.

The renderer also fills the workflow version with the commit the helper runs from,
because every commit between releases shares one version number. When the helper came
from `shakacode/shaka`, the row shows the short commit as a link to it on GitHub, such as
[`d2654ce`](https://github.com/shakacode/shaka/commit/d2654cedfe52975917112c450ebbd7e1bb75afc2).
A commit from a fork or an unrecognized source may not exist there, so the row shows its
full ID without a link. The source is the repository the installer recorded, or a direct
checkout's `origin` remote once one of its fetched `origin` branches contains the commit,
so a local commit is linked only after it is pushed.
For a managed installation, that commit is the revision the installer recorded; edits
to the installed copy afterwards go undetected, as they do in `shaka doctor`, and a
commit installed before it was pushed is linked anyway. For a
checkout the skill runs from directly, it is that checkout's HEAD. `(modified)`
follows the link when the skill's files differed from that commit at installation,
or, in a checkout, when Git reports changes or flags a skill file to skip them. When
no commit can be found, the row shows the release version instead, such as
`0.1.0.pre.1` (commit unknown).

The table shows the latest publication, so `description` also keeps a history in a hidden
marker in the PR body. It adds an entry, recording the PR head, whenever the Workflow version
cell or a route differs from the last entry; republishing the same values adds nothing. Once
there are two entries, a collapsed **Provenance history** block lists them oldest first. It
keeps the first entry and the 20 most recent, and says how many it omitted. The helper writes
this history; a details item with that summary is refused, and so is a marker it cannot
validate, which publishes nothing until the marker is restored or removed. A PR published
before this history existed starts one at its next publication, and a fork's history is never
carried, because the fork author can edit it.

Native usage remains the observed execution record. Provenance does not accept
prompt text, reasoning, transcripts, local paths, run IDs, or arbitrary metadata.
Compare like tasks and coverage alongside quality, retries, delivery time, and
developer attention before drawing savings conclusions.
