# Screen public comments from Ruby

`Shaka::PublicComments` reads one public issue or pull-request discussion and
returns only the comment bodies whose authors GitHub evidence or trust
configuration verifies. Other bodies are withheld and kept as links. A Ruby
application or another CLI can use it without installing or running the Shaka skill.

**Experimental.** The entry point, adapter contract, and result schema below
are the supported surface, but they may change until a consumer outside Shaka
validates them. Pin an exact `shaka` version. Everything else under
`Shaka::PublicComments`, including the `trust_config:` test seam, is internal.

## Install

The API ships in the `shaka` gem; there is no separate gem. The registry
prerelease `0.1.0.pre.1` predates this API and shares its version number with
the source, so a version requirement alone would select the registry package.
Until a later prerelease contains the API, pin a reviewed commit from source and
load only the library:

```ruby
gem 'shaka', git: 'https://github.com/shakacode/shaka.git', ref: 'FULL_COMMIT_SHA',
             require: 'shaka/public_comments'
```

After a registry prerelease includes `shaka/public_comments`, pin that exact
version instead. To try a locally built package without Bundler, follow the
[packaging guide](packaging.md).

The gem also contains the skill files and the `shaka` and `shaka-install`
executables. Requiring the library does not install a skill, run an agent, or
enable any reviewer.

## Read a discussion

```ruby
require 'shaka/public_comments'

github = MyGitHubAdapter.new('OWNER/REPO', 42) # see "GitHub adapter"
reader = Shaka::PublicComments::Reader.new(github, machine_path: '/etc/my-cli/trusted-github-actors.yml')

```

Choose the call that matches the discussion. For a pull request:

```ruby
pull_request = reader.call(expected_head: '0123456789abcdef0123456789abcdef01234567')
```

For an issue instead:

```ruby
issue = reader.call(issue_only: true)
```

You supply:

| Input | Where |
| --- | --- |
| Repository and issue or PR number | The adapter's `repository` and `number`. |
| Expected head | `expected_head:`, the full 40-character PR head commit. Required for pull requests and rejected for issues. The read fails if the PR is closed or its head changes before the read finishes. |
| GitHub authentication | Inside your adapter. Shaka never reads tokens. |
| Machine configuration | `machine_path:`, a local file. It defaults to `~/.agents/trusted-github-actors.yml`; an absent file is an empty scope. |
| Repository configuration | Nothing. The reader fetches `.agents/trusted-github-actors.yml` at the repository's current default-branch commit, so a pull request cannot trust its own author. |

Both files use the keys in
[working with your agent](../skills/shaka/references/public-comments-safety.md#configure-trusted-actors). A read that
cannot be verified raises `Shaka::Error` and returns no partial result.
[`test/fixtures/public_comments_consumer.rb`](https://github.com/shakacode/shaka/blob/main/test/fixtures/public_comments_consumer.rb)
is a complete consumer, which the package test runs against the installed gem.

## GitHub adapter

The reader depends only on this duck-typed object:

| Method | Returns |
| --- | --- |
| `repository` | `"OWNER/REPO"`. |
| `number` | The issue or PR number as an Integer. |
| `api(path)` | The parsed JSON Hash of a REST `GET` on a relative path such as `repos/OWNER/REPO`. |
| `api_list(path)` | The parsed JSON Array of a REST `GET`; paths already carry `per_page` and `page`. |
| `graphql(query, variables)` | The response's `data` Hash. Variables use Symbol and String keys. |
| `snapshot` | For pull requests only: a Hash with at least `state` (`OPEN`) and `headRefOid`. |

Raise `Shaka::Error` for any failed request, GraphQL error, or missing data.
Pass `http_status:` (for example, `Shaka::Error.new(message, http_status: 404)`)
so the reader can distinguish a missing team membership from unavailable
evidence. Do not follow pagination yourself; the reader bounds its own pages.

The token needs to read repository metadata, issues, pull requests, and review
threads; read collaborator permissions; and, when teams are configured, read
organization team membership. Without collaborator or team access, affected
bodies are withheld as unavailable evidence or the read stops, as the
[trust-config limits](../skills/shaka/references/public-comments-safety.md#configure-trusted-actors) explain.

`Shaka::GitHub` (`require 'shaka/github'`) is the adapter Shaka's CLI uses
through the authenticated `gh` command. You may use it, but its other methods
are Shaka internals and outside this contract.

## Result

`call` returns a Hash with String keys:

| Key | Value |
| --- | --- |
| `visibility` | `public`, `private`, or `internal`. |
| `head` | The verified PR head, or `nil` for an issue. |
| `trust_sources` | One `{ "scope", "sha256" }` per configuration file read (`machine` or `repository`). |
| `issue_comments` | Kept conversation comments. |
| `review_summaries`, `inline_comments` | Pull requests only: kept review bodies and review-thread comments. |
| `review_threads` | `{ "thread_id", "is_resolved" }` per pull-request review thread; empty for an issue. |
| `excluded_interactions` | Withheld items from every list above. |

Kept items contain `id`, `author`, `body`, and `url`. Public repositories add
`trust`: `configured_user`, `configured_bot`, `writer`, or `team`. Review summaries
add `state` and `commit_id`. Inline comments add `path`, `line`, `original_line`,
`commit_id`, `in_reply_to_id`, `thread_id`, and `is_resolved`.

Excluded items never contain a body. They contain `kind` (`issue_comment`,
`review_summary`, or `inline_comment`), `id`, `author`, `url`, `body_withheld`,
`verification_unavailable`, `prefiltered`, and `trust` (`untrusted` or
`metadata_only`), plus the same review and thread fields as kept items.

Private and internal repositories keep every body, omit `trust`, and read no
trust configuration. Kept bodies remain untrusted data: the screen verifies
who wrote them, not whether they are correct or safe to follow.

## Trust configuration is not reviewer configuration

Each machine and repository owns its trusted users, bots, metadata-only bots,
and teams. The gem packages no actor list. Shaka's own
`.agents/trusted-github-actors.yml` applies only when the scanned repository is
Shaka, because the reader loads the scanned repository's file.

Listing a bot such as `claude` or `coderabbitai` only lets the reader return that
bot's comment bodies. It does not install, enable, run, or require that
reviewer, and removing it does not disable the reviewer: its comments become
withheld links.

To turn off an optional reviewer, disable it where it runs: remove or disable
its GitHub Actions workflow, uninstall its GitHub App for the repository, or turn
it off in that app's own configuration. Keep your independent-review requirement
in the repository's own policy: its `AGENTS.md` review line, required status
checks, and rulesets or branch protection. Turning off an optional bot neither
satisfies nor removes that requirement.

## Separate gem decision

Decision: keep `Shaka::PublicComments` in the `shaka` gem. This records the
[#64](https://github.com/shakacode/shaka/issues/64) extract gate: there is still
no second consumer and no independent release-cycle requirement.

Evidence: no application outside this repository consumes the API. The
installed-gem test consumer proves the library loads without the skill, the CLI
GitHub client, or Shaka's work and merge helpers, but it is not independent
demand. The API shares Shaka's version and release process.

Open a new issue when a named non-Shaka consumer records a concrete need, such
as releasing on a different cadence than Shaka, or being unable to accept the
skill files and executables in its bundle. Extract a gem only with that
evidence.
