# G2 mutation testing

Measured 2026-11-22 with nim-muter 0.2.18, mutators AOR ROR LOR BLR SDL RVR LBR CVR. Survivors are
classified in `survivors.json`; `nim-muter-ledger check survivors.json` exits 0 only when none is
undecided, test_owed or spec_question. **It does not exit 0 yet: 10 survivors are spec_question**
(listed below), waiting for a decision on what the specification should promise.

| Module | Tests run per mutant | Mutants (compile errors left out) | Killed at first | Killed now | Timeouts | Survived |
|---|---|---|---|---|---|---|
| `profile.nim` | — | 0 (declarations only) | — | — | — | — |
| `runner.nim` | `tests/test_runner.nim` | 62 | 40 | 49 | 1 | 12 |
| `container.nim` | `tests/test_container.nim` | 32 | 22 | 24 | 0 | 8 |
| `spec.nim` | modern-cli-knowledge `test_parse`, `test_spec`, `test_dataset`, and `tests/test_profile.nim` | 129 | 91 | 118 | 2 | 9 |
| `dataset.nim` | same | 62 | 48 | 52 | 1 | 9 |
| `pages.nim` | same | 176 | 138 | 163 | 5 | 8 |

Timeouts are mutants that never finish (a dropped `inc`, a loop condition turned around); they are
detected, and counted apart from killed.

The 46 survivors: 25 equivalent, 5 unreached, 6 accepted, 10 spec_question.

- accepted: `defaultTimeoutMs` (120 s, SHPG-RUN-05) can only be told from 120001 by a 120-second
  test or one that pins the constant; five mutants change only the wording of an error that is
  still reported for the same row.
- spec_question:
  - no row promises that a run leaves no temporary directory behind (runner, container) or that
    the process handle is closed (runner);
  - `SpecRow.line` is public, but no row says which line number a table row carries;
  - no row says how a title whose colon is its first character gives its tool (spec, dataset);
  - MCLI-PAGE-03 does not say whether a zero-padded `# exit: 0001` is refused.

## Running it again

- The modules `pages`, `spec` and `dataset` are specified and tested in modern-cli-knowledge, which
  reaches this package through `--path:"../nim-shell-pages/src"` in its `nim.cfg`. nim-muter runs
  each mutant in a shadow copy of the workspace, so a test command that only changes into a copy
  of modern-cli-knowledge compiles the unmutated package and every mutant survives; adding
  `--path` on the command line does not help, because the configuration file wins. The campaign
  used a copy of modern-cli-knowledge whose `nim.cfg` points at a fixed name next to it, and a test
  command that links that name to the shadow copy's root before compiling. Check the arrangement
  first: with the title heading of `pages.nim` emptied by hand, modern-cli's `test_parse`,
  `test_spec` and `test_dataset` must fail.
- Campaigns run in copies without the VCS directories, as described in nim-cs-knowledge's
  `docs/quality/g2-mutation.md`, with `DEVELOPER_DIR=/Library/Developer/CommandLineTools` when
  Xcode's licence blocks the C compiler.
- `container.nim` needs podman and the image `docker.io/library/ubuntu:24.04`.
- Then `nim-muter-ledger sync <outputDir>/report.json docs/quality/survivors.json` and
  `nim-muter-ledger check docs/quality/survivors.json`.
