# Install-local repository catalog

Shaka does not keep a central fleet registry. Each repository owns its display prefix
in the trusted `.agents/agent-workflow.yml` seam. An installation may rebuild a local
catalog of repositories it already knows about. That catalog is convenience data: it
is safe to delete, and missing or stale entries must not block `shaka seam check`,
`shaka prefix`, or other work inside a checkout.

Use the catalog to identify duplicate prefixes and repositories whose settings
need comparison. It reports duplicates; it does not enforce uniqueness or update
repository policy. See the [product guide](https://github.com/shakacode/shaka/blob/main/docs/repository-catalog.md).

## Location

Default home is `$SHAKA_HOME`, or `~/.shaka` when that variable is unset.

| Path | Role |
| --- | --- |
| `$SHAKA_HOME/repos.yml` | Registered checkout roots. Discovery source. |
| `$SHAKA_HOME/catalog.json` | Rebuilt index. Safe to delete. |

Neither file belongs in a public repository. Do not copy private repository names
into public artifacts.

## Discovery

`shaka repos add --root DIR` appends a realpath to `repos.yml`. Hosts may write the
same file themselves. Discovery stays in this install-local command; it does not
live in the portable GitHub or merge modules, and it does not scrape GitHub orgs.

A missing `repos.yml` is an empty root list. Refreshing then writes an empty
catalog.

## Refresh

```bash
shaka repos refresh
```

For each registered root, refresh reads `origin` for identity and canonical URL,
then loads the trusted default-branch seam from `origin/HEAD`, falling back to
`origin/main` or `origin/master` when that symbolic ref is missing. It does not trust
a candidate working tree. The effective prefix is the seam `repo_prefix` when
present, otherwise the [documented fallback](https://github.com/shakacode/shaka/blob/main/docs/settings.md#repo_prefix).

Stdout and `catalog.json` use the same object:

```json
{
  "version": 1,
  "repositories": [
    {
      "identity": "shakacode/shaka",
      "url": "https://github.com/shakacode/shaka",
      "root": "/path/to/shaka",
      "prefix": "SHAKA",
      "prefix_source": "seam"
    }
  ],
  "duplicate_prefixes": {}
}
```

`identity` is always `owner/name`. Duplicate prefixes across **distinct**
`host/owner/name` keys are listed under `duplicate_prefixes` and printed on stderr;
refresh still writes the catalog and exits non-zero so a collision cannot silently
select the wrong repository. Two checkouts of the same host and identity with the
same prefix are not a collision. The same `owner/name` on different hosts is a
collision when the prefixes match. Distinct non-default ports on the same host are
distinct repositories. Catalog `url` values never keep remote userinfo,
query strings, or fragments; userinfo ends at the last `@` in the authority, and
SCP remotes catalog as `ssh://host/owner/name`. A missing or unreadable registered
root is skipped with a stderr warning; refresh still writes the remaining rows and
exits non-zero.

## Direct operation

`shaka prefix --root DIR --ref REF` resolves one repository without reading the
catalog. Removing `catalog.json` does not remove seam metadata.

`prefix_source` records how the prefix was obtained: `seam` means explicit trusted
configuration; `fallback` means a name derived from the repository. Keep that
distinction so a cached suggestion cannot be mistaken for a configured prefix.
