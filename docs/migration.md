# Upgrade an installation

Ask your agent:

```text
Update my Shaka installation. Preserve my customizations and check whether
this repository needs configuration changes. Keep its review and merge choices.
```

For a fork, compare upstream changes first. The agent follows the
[upgrade procedure](../skills/shaka/references/migration.md) and prepares any needed
repository configuration changes for review.

If the repository already has a valid version-one Shaka configuration under
`.agents/`, ask: “Upgrade this repository's Shaka configuration layout.” The agent
will preview the moves and repairs for review before applying them. The
[layout upgrade procedure](../skills/shaka/references/migration.md#upgrade-the-configuration-layout)
explains recovery and validation. Existing legacy layouts remain readable while a
migration PR is under review.

Automatic update notifications are not currently implemented.
