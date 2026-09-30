# Writing preferences

Shaka's installed skill provides [default writing guidance](https://github.com/shakacode/shaka/blob/main/skills/shaka/references/writing.md)
for PR descriptions, code walkthroughs, and review replies. Installing Shaka does
not create or edit `AGENTS.md`, and these defaults work without that file.

For a task, tell the agent how you want it to write:

```text
Keep PR descriptions short. Lead with what changed for the user,
use before/after examples, and put implementation details in the walkthrough.
```

For persistent repository preferences, you may create or edit `AGENTS.md` yourself.
You may link to a separate file when the guidance is long or has a distinct
audience. For example:

```text
When writing this repository's product guides, read docs/editorial-style.md.
```

When trusted `AGENTS.md` exists, the Shaka workflow instructs the agent to follow
its writing preferences and any style file it explicitly links. Shaka's Ruby
helpers do not automatically load a linked file or verify editorial style.

Shaka also checks each description and walkthrough before publishing it. Text
that reads as a wall is not published; the agent shortens it and tries again, and
the description's collapsed review history notes each retry. The
[`prose_limits`](settings.md#prose_limits) setting explains the checks and how to
change them.
