# nim-shell-pages

Shared machinery for repositories of tested command-line knowledge: Markdown pages, one per task,
whose shell examples are run and compared byte for byte. It is used by modern-cli-knowledge and
unix-admin-knowledge (ADR-SHPG-0001).

| module | what |
|---|---|
| `src/shell_pages/profile.nim` | `PageProfile`: everything that differs between the repositories (section names, spec-ID prefix, text-only categories, dataset wording); passed in, never a literal here |
| `src/shell_pages/pages.nim` | the page parser: title and tool, sections, code blocks, and the pairing of a command with its expected output (`# exit: N`, `# spec: …`, `classic`, `bad`, `idempotent`) |
| `src/shell_pages/spec.nim` | the spec-table check: every claim of a page has a row, and every row points at an example or says why it is text only |
| `src/shell_pages/dataset.nim` | the dataset derivation: `records.jsonl` and `chat.jsonl` records from verified pages only |
| `src/shell_pages/runner.nim` | the local runner: a fresh copy of a fixture tree, a fixed environment, `sh -c`, output and status compared |
| `src/shell_pages/container.nim` | the container runner: the same, inside `podman run --rm --network none`, with only `NET_RAW`, `NET_ADMIN` or `SYS_ADMIN` added on request |

What each part promises is in `docs/specification.md` (IDs `SHPG-*`). The page rules themselves
(`MCLI-PAGE-*`, `MCLI-EX-*`, `MCLI-SPEC-*`, `MCLI-DATA-*`) are specified and tested in
modern-cli-knowledge through its profile; `tests/toy_profile.nim` checks that no value here is
borrowed from a real repository.

## Use

```nim
import shell_pages/[pages, runner]

let page = parsePage(readFile("skills/x/details/find-files.md"))
for ex in examplesOf(page, myProfile).examples:
  let outcome = checkExample("fixtures/tree", "/tmp/work", ex)
  if not outcome.ok: echo outcome.message
```

A repository puts `--path:"../nim-shell-pages/src"` in its `nim.cfg`; the package has no other
dependency and builds no executable.

## Development

```sh
nim test           # every tests/test_*.nim (the container tests need podman and ubuntu:24.04)
nim specCoverage   # G1 table → docs/quality/g1-spec-coverage.md (needs ../nim-spec-coverage)
```

Mutation testing (G2) is described in `docs/quality/g2-mutation.md`, its survivors in
`docs/quality/survivors.json`.

## Licence

Apache License 2.0 (`LICENSE`, `NOTICE`).
