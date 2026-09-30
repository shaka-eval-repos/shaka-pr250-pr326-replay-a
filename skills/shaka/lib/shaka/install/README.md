# Installer terms

The installer copies the selected Shaka skills from a source checkout into a
managed directory. It calls each complete, retained copy a **package**. This is
a directory of skill files and installation metadata, not a Ruby gem or npm
package. For example, a `shaka` package contains `skills/shaka/SKILL.md`, its
references, scripts, Ruby helper, and configuration.

The code in this directory handles four parts of that installation:

- `Package` builds a temporary copy, checks that it matches the source, then
  renames it into the managed directory. Copied files belong to the installing
  account. It removes group and world write bits from copied files and
  directories; the content hash records those copied modes. Earlier packages
  remain for rollback.
- `Links` points the coding agent's skill link, such as
  `~/.agents/skills/shaka`, at the finished package. “Switch” means replacing
  that link. An “owned host link” is an existing skill link whose target matches
  this Shaka source or the expected managed package path; the installer leaves
  unrelated destinations alone. This path check does not prove who created a
  package.
- `Source` records the copied files' Git revision when the source is the
  repository root, selected files and directories match the tracked tree,
  selected paths have clean Git status, raw file bytes and executable modes
  match `HEAD`, and no selected file is world-writable. Otherwise, it records a
  development installation with a content hash and, when available, a base revision.
- `Version` reads the Shaka product version from `skills/shaka/lib/shaka/version.rb`
  without running that file. It does not read a repository workflow setting.

After installation, the agent uses the managed copy through its skill link. The
original source checkout can be removed without breaking that installed skill.
