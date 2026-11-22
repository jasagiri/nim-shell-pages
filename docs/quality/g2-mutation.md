# G2 mutation testing

Measured 2026-11-22 with nim-muter 0.2.18, mutators AOR ROR LOR BLR SDL RVR LBR CVR, and measured
again the same day after the spec questions of the first measurement were decided (SHPG-PAGE-01,
SHPG-SPEC-01, SHPG-RUN-07, SHPG-CONTAINER-11, the value of `defaultTimeoutMs` in SHPG-RUN-05, and
the zero-padded exit line in modern-cli-knowledge's MCLI-PAGE-03). Survivors are classified in
`survivors.json`; `nim-muter-ledger check survivors.json` exits 0 only when none is undecided,
test_owed or spec_question.

| Module | Tests run per mutant | Mutants (compile errors left out) | Killed | Timeouts | Survived |
|---|---|---|---|---|---|
| `profile.nim` | — | 0 (declarations only) | — | — | — |
| `runner.nim` | `tests/test_runner.nim` | 62 | 52 | 1 | 9 |
| `container.nim` | `tests/test_container.nim` | 32 | 25 | 0 | 7 |
| `spec.nim` | modern-cli-knowledge `test_parse`, `test_spec`, `test_dataset`, and `tests/test_profile.nim` | 123 | 116 | 2 | 5 |
| `dataset.nim` | same | 56 | 48 | 1 | 7 |
| `pages.nim` | same | 182 | 170 | 5 | 7 |

Timeouts are mutants that never finish (a dropped `inc`, a loop condition turned around); they are
detected, and counted apart from killed.

The 35 survivors: 25 equivalent, 5 unreached, 5 accepted, none undecided, test_owed or
spec_question; `nim-muter-ledger check docs/quality/survivors.json` exits 0.

- accepted: five mutants change only the wording of an error that is still reported for the same
  row.
- The first measurement left 10 spec_question survivors. Each became a row and a test: a run leaves
  no temporary directory and no open file behind (SHPG-RUN-07, SHPG-CONTAINER-11), a table row
  carries its line number (SHPG-SPEC-01), a title whose colon comes first still gives its tool, now
  read in one place for the spec check and the dataset (SHPG-PAGE-01), and `# exit: 0001` is
  malformed (MCLI-PAGE-03). `defaultTimeoutMs` is pinned to the 120 s that SHPG-RUN-05 states, as
  the two exit codes it states already were.

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
