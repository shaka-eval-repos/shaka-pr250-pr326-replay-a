🤖 Claude Code · Anthropic · claude-opus-5-5 · xhigh

The summary uses `<details>` in code. **Reviewers** see the code. iOS builds pass.

[Code Walkthrough](https://github.com/o/r/pull/1#pullrequestreview-1)

## Heading words stay hidden

<!-- <details> -->

<!--
Comment words stay hidden.
-->

Example:

    <details>
    Indented code stays hidden.

Check | Result
--- | ---
Table words stay hidden. | pass

> Quoted words stay hidden.

- Item one
  - Nested item
- Item two with a [link](https://example.com/hidden-address)

<details>
<summary>Usage</summary>

Collapsed words stay hidden.

<details>
<summary>Inner</summary>

Nested collapsed words stay hidden.

</details>

</details>

After details.
