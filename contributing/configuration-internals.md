# Configuration implementation map

For contributors changing Shaka's configuration loader. Agents using Shaka
should follow [repository setup](../skills/shaka/references/repository-setup.md).

For settings and examples, read [Configuration](../docs/settings.md). This map
shows where Shaka reads and enforces them.

| Input | Consumer | Authority |
| --- | --- | --- |
| `.agents/agent-workflow.yml` | `shaka seam check --ref SHA` | Policy from the resolved default-branch commit |
| `.agents/bin/*` | Agent and CI | Optional capability from the trusted commit; executable code from the candidate checkout |
| `.agents/trusted-github-actors.yml` | `shaka comments` | Current default-branch allowlist, combined with the machine allowlist |
| `AGENTS.md` | Agent | Trusted repository instructions; candidate edits are review data |

Inspect candidate script changes before execution. `--local` checks the candidate
contract and grants no authority.

## Packaged workflow

| File | Command | Purpose |
| --- | --- | --- |
| [`workflow.yml`](../skills/shaka/config/workflow.yml) | `shaka workflow` | Validate and render the ordered agent procedure |
| [`enforcement.yml`](../skills/shaka/config/enforcement.yml) | `shaka enforcement` | Report which rules are enforced by code, GitHub, or the agent |

The enforcement loader checks that quoted rules still exist and that strong-rule
phrases are classified. It cannot detect a new clause inside an already quoted
passage or judge whether a classification is true. Review those changes manually.

## Ruby implementation

Paths below are relative to `skills/shaka/lib/shaka/`.

`Shaka::Configuration` in `configuration.rb` is the caller interface. Use
`worktree(root:)` for candidate settings and `trusted(root:, ref:)` for policy at
an immutable commit; a missing or invalid trusted contract never falls back to
the worktree. `Paths` owns repository and machine filenames, directory names,
and standard executable names. Callers use `path`, `command_path`, and the
source-specific helpers for prompt selection, predecessor reads, and generated
destinations. The old `RepositoryConfig` and `TrustedConfigSource` classes remain
focused internals behind this interface. `configuration/trust_config.rb` owns
allowlist source selection; its former require path is a compatibility shim.

The boundary covers repository-facing settings, allowlists, executable discovery,
and seam initialization and migration. `configuration/generated_files.rb` restricts
generated-file reads and writes to the known destinations. Packaged `workflow.yml`, `enforcement.yml`,
and usage rate data have separate loaders; the install-local repository catalog
and GitHub metadata are also separate. Generated pointer text and error messages
may show concrete paths as explanations. The merge-review classifier names
`.agents/` as an instruction directory, not a configuration source. The architectural
test flags `.agents` literals, selected `File` calls, and quoted Git reads outside
the boundary. Its allowlist records unrelated file I/O. Code search must still
review other APIs and dynamically assembled access; the scan does not prove
complete encapsulation.

| Concern | Source |
| --- | --- |
| Public access and path ownership | `configuration.rb`, `configuration/paths.rb` |
| Generated file reads and writes | `configuration/generated_files.rb` |
| YAML loading and effective defaults | `repository_config.rb` |
| Root keys and values | `repository_config/schema.rb` |
| Fixed scripts and optional dependencies | `repository_config/command_paths.rb`, `command_schema.rb` |
| Trusted refs and symlink authorization | `trusted_config_source.rb` |
| Review settings and selection | `repository_config/review_schema.rb`, `reviewer_selection.rb`, `ci_review_wait.rb` |
| Branch template | `repository_config/branch_schema.rb` |
| WIP location setting | `repository_config/wip_schema.rb` |
| Duplicate keys and document count | `repository_config/duplicate_keys.rb` |
| Initial configuration | `seam/initializer.rb` |
| Migration classification | `seam/field_classifier.rb` |
| Trusted repository and machine allowlists | `configuration/trust_config.rb`, `configuration/trust_settings.rb` |

See [development](development.md) for the repository's other config
files, executable entry points, and checks.
