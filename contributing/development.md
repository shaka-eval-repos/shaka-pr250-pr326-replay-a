# Developing Shaka

Read [AGENTS.md](https://github.com/shakacode/shaka/blob/main/AGENTS.md) before changing the project. Runtime code uses Ruby's
standard library and `gh`; development adds Minitest and RuboCop through Bundler.

```bash
.agents/bin/setup
.agents/bin/test test/repository_config_test.rb
.agents/bin/validate
```

`setup` installs dependencies for working on Shaka. `bin/install` instead links
Shaka skills into a coding agent's skills directory. `test` accepts test paths;
`validate` chooses appropriate checks. `bin/validate` runs all tests and lint.

## Where changes belong

| Location | Purpose |
| --- | --- |
| `docs/` | Product guides and settings |
| `skills/shaka/config/workflow.yml` | Ordered agent instructions |
| `skills/shaka/config/enforcement.yml` | Which rules code or the agent enforces |
| `skills/shaka/references/` | Procedures loaded by skills when needed |
| `skills/shaka/lib/shaka/` | Ruby implementation |
| `contributing/` | Development, packaging, and release guidance |
| `internal/` | Public plans, trials, and temporary migration records |

Run `shaka workflow` and `shaka enforcement` after changing the workflow. Check
relative links and packaged references when moving documentation. A passing
link check does not establish usability; use a representative reader task for
a substantial rewrite. See [configuration internals](configuration-internals.md)
for parser and policy boundaries.
