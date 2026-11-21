# ADR-SHPG-0001: One page machinery for command-knowledge repositories

**ADR ID**: ADR-SHPG-0001
**Status**: accepted
**Date**: 2026-11-21
**Author**: jasagiri (drafted by Claude Opus 5.5)

## Context

modern-cli-knowledge keeps its knowledge as Markdown pages whose shell examples are run and
compared byte for byte, with a spec table per page and a training dataset derived from the pages.
The parser, the spec-table check, the dataset derivation and the runner lived in its `src/mcli/`.
A second repository of the same kind, for system administration tools, needs the same machinery,
with two differences: other section names and spec-ID prefix, and examples that must run inside a
Linux container because they need root, kernel state or capabilities a local scratch copy does not
give.

## Requirements

- One implementation answers "is this page well formed, do its examples print what it says, which
  records does it give"; a fix reaches every repository that uses it.
- Moving the code out of modern-cli-knowledge changes none of its results: its tests pass and its
  dataset keeps the same bytes.
- A repository-specific value (section names, ID prefix, text-only categories, dataset wording)
  is data passed in, not a literal in the shared code.
- A container run cannot reach the network and cannot be given more than the capabilities an
  example declares from a fixed list.

## Options

- A. Extract the machinery into this package; each repository passes a `PageProfile` value.
- B. Keep it in modern-cli-knowledge, add parameters there, and have the other repository import
  it by path.
- C. Copy it into the second repository and adapt the copy.

## Trade-offs

- A costs one more repository and a profile value in each user; the shared code no longer knows
  any repository by name.
- B needs no new repository, but the second repository then depends on a page collection to get a
  library, and modern-cli-knowledge carries code that is not about modern tools.
- C is quickest, and then two copies answer the same question and drift when only one is fixed.

## Decision

A (decided by jasagiri on 2026-11-21).

- `shell_pages/profile.nim` holds `PageProfile`: required sections and headings, bullet letters,
  spec-ID prefix, text-only categories, and the dataset's area, spec IDs, record kinds, wording and
  system message. The parser, spec check and dataset take it as a parameter; `parsePage`,
  `withoutHeader` and the local runner kept their signatures.
- `shell_pages/runner.nim` is the local runner moved unchanged (copy of a fixture, fixed
  environment, `sh -c`).
- `shell_pages/container.nim` runs a command with `podman run --rm --network none`, the work
  directory mounted at `/work`, the same fixed environment, and `--cap-add` only for `NET_RAW`,
  `NET_ADMIN` and `SYS_ADMIN`. Anything else, an image name that starts with `-`, or a work path
  that would split the mount option, is refused before podman runs, as a result with status
  `refusedExitCode` (1000, outside the 0 to 255 range of a real exit status) rather than an
  exception, because the caller can read and fix it. `--privileged` is never passed.
- The page rules of modern-cli-knowledge (MCLI-PAGE, MCLI-EX, MCLI-SPEC, MCLI-DATA) stay specified
  and tested there, through its profile; this package specifies what it adds (SHPG-PROFILE,
  SHPG-RUN, SHPG-CONTAINER in `docs/specification.md`).
- Users reach the package by a sibling path (`--path:"../nim-shell-pages/src"`), as they already
  reach other sibling packages.

## Not decided here

- Publishing this package to a package index.
- Running examples for one repository on more than one platform.

## Rejected alternatives

- B and C, for the reasons under Trade-offs.
