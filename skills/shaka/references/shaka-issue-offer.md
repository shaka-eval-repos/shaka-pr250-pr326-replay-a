# Shaka issue-offer procedure

Follow this procedure when the Shaka workflow's **Always** guidance says to offer an issue for a
worthwhile, verified product gap. Only the root task owner runs it; workers report possible gaps to
that owner.
Respect a user request to skip offers for the current task. Keep the current task moving while the
user considers the offer.

## Offer before searching

Offer a clear, actionable gap worth tracking, not every idea set aside by the active task. For an
AI-found gap or uncertain value, use the Shaka
[value checkpoint](delivery.md#say-what-the-work-is-worth);
keep missing impact and frequency UNKNOWN, and skip offers that remain speculative or low-value. Draft a concise
title and body from public sources. Verify the gap in current public Shaka materials
and cite that source in the draft; cite public sources for other factual claims. Exclude details
learned only from the active task or a private repository, as well as private repository names,
branches, file paths, and links. Choose two to four distinctive alphanumeric terms from the public
draft, separated by spaces. Do not include punctuation, symbols, or the standalone words `AND`,
`OR`, or `NOT` in any case; GitHub documents `NOT` as an exclusion operator in its
[search syntax](https://docs.github.com/en/search-github/getting-started-with-searching-on-github/understanding-the-search-syntax).
The `--` separator stops CLI option parsing, but GitHub still parses query operators. If no safe
query can be formed, explain why; do not search or file, and continue the active task. When a safe
query is available, show the exact title, body, source links, and query.
Ask whether the user authorizes that search; tell them you will ask again before filing. Continue
the active task while waiting. Do not search if the user declines or has not accepted. If the
accepted text or query changes, show the full revision and ask again.

## Verify the target and search

After acceptance, verify the target is the fixed public Shaka repository on GitHub.com,
`github.com/shakacode/shaka`. Run `GH_HOST=github.com gh repo view shakacode/shaka --json id,nameWithOwner,visibility` and
require live values to match node ID `R_kgDOUZzTGw`, canonical name `shakacode/shaka`, and public
visibility `PUBLIC`. Stop and report any command failure or mismatch before searching.
If the live identity no longer matches because Shaka has legitimately moved or been recreated,
stop and report it. A maintainer must verify and update the pinned identity through the normal
Shaka review process before another search or filing attempt. GitHub CLI calls resolve this
repository by its name, not node ID; a move after either identity check remains a narrow race the
procedure cannot eliminate.

Search every issue and pull-request state; omit `--state`. Run two metadata-only searches with the
same query, one for issues and one for pull requests. Keep them separate even when a combined
search works for you: GitHub
[returns HTTP 422](https://docs.github.com/en/rest/search/search#search-issues-and-pull-requests)
for a combined search made with a GitHub App user access token. Either search failing or hitting
its limit fails the whole check. Ask GitHub to match titles and bodies, and return only number,
URL, and state:

```sh
GH_HOST=github.com gh search issues --repo shakacode/shaka --match title,body --limit 1000 \
  --json number,url,state -- "$QUERY"
GH_HOST=github.com gh search prs --repo shakacode/shaka --match title,body --limit 1000 \
  --json number,url,state -- "$QUERY"
```

Pass `QUERY` after `--` on each command as one safely quoted argument. The separator prevents a
leading hyphen from becoming a CLI option. Options such as `--jq` placed after `--` become query
text. The term rules above prevent GitHub from treating query text as an operator.
This best-effort check can miss duplicates when GitHub has no matching indexed text; no results is
not proof no issue exists. A result is a possible duplicate, not a confirmed match: share its
returned URL, number, and state, say whether the issue search or the pull-request search returned
it, and wait for the user to inspect it. Do not request or fetch titles, issue or pull-request
descriptions, or comments. If either search fails or returns 1,000 results, the whole check fails:
report that and do not file an issue. If both searches return no candidates, share the query and
the zero-result outcome, then ask whether the user authorizes creating the exact issue.

## File accepted text

If there were no candidates, file only after the user accepts the zero-result caveat and explicitly
authorizes creation. If there were candidates, file only after the user confirms none covers the gap
and explicitly authorizes creation. Reverify the repository identity, then repeat both searches
with the exact approved query. If either search fails or either reaches the 1,000-result limit,
the whole check fails; do not file. Compare the returned candidate metadata with the results the
user reviewed, including which search returned each row. If any candidate is new or its metadata
changed, share the updated metadata and wait for the user's inspection and renewed explicit
approval before filing. If no candidate metadata changed, the existing filing approval remains
sufficient. File only after the latest candidates are reviewed and the user confirms none covers the
gap. Do not repeat the searches after renewed approval; a candidate opened after the final recheck
is a narrow race the procedure cannot eliminate.

Pass the exact approved text to the installed Shaka CLI's `issue-create` subcommand in a quoted
here-document: put the single-line title first and the approved body on the remaining lines, and
choose a delimiter that appears nowhere in either value. Use the executable path established by
installation; the gem exposes `shaka`, and the source installer prints the installed
`skills/shaka/scripts/shaka` path. The command rechecks the fixed public repository identity on
GitHub.com, streams the exact body to `gh`, and prints the resulting public issue URL. It removes
the one final newline used to terminate the here-document. To preserve an approved body that ends
with a newline, include one extra blank line before the delimiter. If the command does not return
the issue URL, stop and inspect live repository state before any retry.
