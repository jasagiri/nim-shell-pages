# Specification: nim-shell-pages

Repository-level behaviour. Each row is one spec ID; tests carry `# SPEC: <ID>`. The parser, the
spec-table check and the dataset derivation moved here unchanged from modern-cli-knowledge; their
page-shape, example-pairing, spec-table and dataset rules (MCLI-PAGE-*, MCLI-EX-*, MCLI-SPEC-*,
MCLI-DATA-*) stay specified and tested in that repository, through its profile. The rows below are
what this package adds.

## Profile

| ID | Statement |
|---|---|
| SHPG-PROFILE-01 | The sections a page must have, and their order, are the profile's `requiredSections`; a missing or misplaced one is named. |
| SHPG-PROFILE-02 | A `# spec:` line holds IDs of the form `<specIdPrefix>-<TOOL>-NN` only; the error names the profile's prefix. |
| SHPG-PROFILE-03 | The spec-table check reads the profile's headings, bullet letters, ID prefix and text-only categories; no other value decides. |
| SHPG-PROFILE-04 | A dataset record takes its ID namespace and `area`, its spec IDs, its `kind` for the keep record, its instructions, its labels and its system message from the profile, and its file path from `pagesDir`. |
| SHPG-PROFILE-05 | An idempotent example's record carries the profile's idempotence spec ID besides the example ID. |

## Local runner

| ID | Statement |
|---|---|
| SHPG-RUN-01 | A fixture is copied with each `_gitignore` renamed `.gitignore` and an empty `.git` directory at the root. A work directory that already exists is kept and emptied, not removed and made again, so a container that mounts it sees the new copy. |
| SHPG-RUN-02 | A command runs with `sh -c` in the copy, under the fixed environment, with standard output, standard error and status kept apart. |
| SHPG-RUN-03 | An example passes when its output and status match; a differing output, a differing status, or a second idempotent run that changes the tree fails and names the line. |
| SHPG-RUN-04 | `checkExampleWith` checks an example as SHPG-RUN-03 states it, with every command (the example, its classic partner, both idempotence runs) run by the routine it is given; `checkExample` is `checkExampleWith` with the local `run`. |
| SHPG-RUN-05 | `run` (and every run, through `runBounded`) gives back standard output and error whole whatever their size, and stops a command still going after its time limit (`defaultTimeoutMs` = 120 s when not given) with status `timedOutExitCode` (1001) and `timed out` on standard error; a command that itself ends with 137 keeps 137. |
| SHPG-RUN-06 | `checkExampleWith` gives every run its own fresh copy of the fixture in a directory under `work` that no earlier run used (the two idempotence runs share one copy), and removes it after the check: a container runtime that shares host directories into a virtual machine can keep a stale view of a reused path. |

## Container runner

| ID | Statement |
|---|---|
| SHPG-CONTAINER-01 | `runInContainer` returns the standard output, standard error and exit status of `/bin/sh -c <command>` run in the container. |
| SHPG-CONTAINER-02 | The container sees `LC_ALL=C.UTF-8 TZ=UTC NO_COLOR=1 TERM=dumb PAGER=cat HOME=/work` and starts in `/work`. |
| SHPG-CONTAINER-03 | Standard input of the command is empty. |
| SHPG-CONTAINER-04 | The work directory is mounted at `/work` read-write; files the command writes there are on the host afterwards. |
| SHPG-CONTAINER-05 | The container has no network beyond loopback (`--network none`). |
| SHPG-CONTAINER-06 | Each allowed capability becomes `--cap-add <cap>`; `--privileged` is never passed. |
| SHPG-CONTAINER-07 | A capability other than `NET_RAW`, `NET_ADMIN`, `SYS_ADMIN` is refused before podman runs: the result has status `refusedExitCode` (1000), empty standard output, and `refused: …` on standard error. |
| SHPG-CONTAINER-08 | An empty image or one starting with `-`, and a work directory that is empty or contains `:` or `,`, are refused the same way. |
| SHPG-CONTAINER-09 | A run still going after its time limit (`timeoutMs`, `defaultTimeoutMs` = 120 s when not given) is stopped: podman is killed, the container is removed, and the result has status `timedOutExitCode` (1001) with `timed out` on standard error. |
| SHPG-CONTAINER-10 | Standard output and standard error come back whole whatever their size, each kept apart. |
