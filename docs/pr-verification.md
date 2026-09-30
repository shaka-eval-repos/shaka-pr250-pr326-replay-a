# PR verification

## Keep the PR easy to read

Lead with the outcome and a short validation result. Put the most useful comparison
beside the explanation; keep longer output and extra captures in expandable
sections. Publish evidence once and link to it from chat.

For example: “The menu stays reachable on narrow screens. The regression test
failed before the fix and passes now; desktop and mobile screenshots show the
result.” Details can hold commands, tested commits, and a recording of the menu.

Shaka uses your existing tests and validation commands, plus browser tools when
needed. Required GitHub checks and approvals still apply.

## Change one behavior at a time

The agent writes a focused test, confirms it fails because the behavior is broken
or missing, then fixes the code and simplifies it while tests stay green. Tests
exercise behavior through public interfaces; matching implementation details or
instruction wording does not prove the result.

When automation is impractical, record the limitation and useful before/after
evidence. Wording edits need documentation checks, not invented failing tests.
Validation can select checks for affected files; required security checks still apply.

## Documentation changes

Check links and rendered pages. For a substantial rewrite, check whether a reader
can complete the intended task. See the agent's
[documentation-verification procedure](../skills/shaka/references/documentation-verification.md).

## Show what a person will see

| Change | Useful evidence |
| --- | --- |
| Layout, styling, or visible output | Test on desktop and mobile; capture before/after screenshots of both, plus a [difference image](#show-what-changed-between-captures) when they align. |
| Interaction, animation, or timing | A short recording, with screenshots where they help comparison. |
| Backend or command-line behavior | Focused tests and concise before/after output. |

Inspect screenshots for the intended state, not an error page, blank screen, or
loading placeholder. Review the relevant video frames to confirm the interaction
is visible. Screenshots and video complement tests.

Use safe test data. Before publishing, check for credentials, private task details,
customer data, and unrelated screen content. Expandable sections on public PRs
are public too.

For any on-screen change other than command-line output, the agent also uses the
change by hand on the head it pushes, and repeats that pass after any later commit
that changes runtime behavior.
When the PR has a preview deployment, it checks the preview too, or says why not.

Attach captures to a PR comment with GitHub CLI 2.99 or later, then open the
comment to confirm each path became an uploaded link. A local path is not shared
evidence.

```sh
gh pr comment 42 --attach './before-desktop.png#Menu before, desktop' \
  --attach './after-desktop.png#Menu after, desktop' --attach './menu-open.mp4'
```

Text after `#` is an image's alt text; a video takes no alt text.

Label the tested commit and behavior. After code changes, refresh affected
evidence or explain which part still applies. When a capture cannot be published,
the PR records why: `uploader_absent` (no attachment route is available),
`uploader_denied` (the upload was refused), or `upload_failed:` with the error.

## Show what changed between captures

A difference image shows a reviewer where the pixels changed, so they need not
compare two screenshots by eye. It also exposes a change nobody meant to make,
such as a shifted footer beside the button the PR restyled.

The two captures have to show the same rendered state: the same route, viewport,
scroll position, test data, and interaction step, at the same image size. Capture
a taller viewport instead of scrolling when the change sits below the fold. Make
one comparison for each view the change affects, usually desktop and mobile.

The agent inspects both captures first, then generates the difference with any
image tool the project already has, such as ImageMagick, following the agent's
[difference-image procedure](../skills/shaka/references/visual-diff.md). Unchanged
pixels fade and changed ones turn red.

Publish the difference beside its source captures in one PR comment, attached the
same way as other captures. Label the compared revisions, the page and state, the
viewport, and whether each changed region is intended, for example “Changed pixels,
pricing page, desktop 1280x800, main 4396e9c to abc1234: new plan card intended,
footer shift unintended.”

A red region is not a defect by itself. Antialiasing, font rendering, and
timestamps also change pixels. Say which regions the PR meant to change and
explain any others.

When animation, live data, or a different page structure keeps the captures from
aligning, or no image comparison tool is available, the agent says why and
publishes the clearest labeled before-and-after pair instead. A short recording
still shows timing and interaction. Check the difference image for private data,
unrelated screen content, error pages, and loading placeholders, the same as its
source captures.

## Show whether it is faster or slower

Some changes aim to speed up page load, rendering, or bundle size, or could slow them.
Others change what a page loads or how it is cached or streamed. For these, the agent
compares the base with the change on pages and metrics that reach the change. It uses
the repository's own benchmark when there is one, and
[ShakaPerf](https://github.com/shakacode/shakaperf#usage) otherwise.

The PR reports the verdict: improvement, wash, regression, or ambiguous. It names the
pages, metrics, sample count, and the base and change commits. Any regression or
ambiguous result, and a wash for an intended speed-up, go back for a fix or for the
maintainer to accept. When no comparison can run, the PR says the speed was not measured.
