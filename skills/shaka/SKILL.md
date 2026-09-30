---
name: shaka
description: Deliver one ordinary task through verified GitHub PRs, splitting only when useful; publish walkthroughs, address review, and honor merge authority.
---

# Shaka

Own one task through its requested PR outcome. `$shaka` (`/shaka` in Claude Code, OpenCode,
and Cursor) alone starts intake. Work solo unless delegation is authorized and useful; reuse
relevant evidence.

Before any branch change, resolve this installed skill to its trusted source outside every
candidate checkout and keep that absolute `scripts/shaka` path for the whole task. Git can
replace a checkout-local skill link. Never load or run a branch-provided replacement skill or
helper. If this skill's own directory resolves inside the checkout, stop and report it.

Run the trusted helper's `workflow` command now and follow the complete validated procedure it
prints. The packaged YAML owns the workflow text; Ruby validates its schema and phase order
before rendering it. If loading or validation fails, stop and report the error instead of
reconstructing the workflow from memory.

`seam init` configures a new repository under `.agents/shaka/`. An existing repository
with version-one configuration directly under `.agents/` keeps working; use the
[configuration layout upgrade](references/migration.md#upgrade-the-configuration-layout)
when you want to move it to `.agents/shaka/`.
