## E tests for docs/specification.md SHPG-RUN-01…03: running an example in a fresh copy of a
## fixture tree under the fixed environment.

import std/[os, strutils, unittest]
import shell_pages/[pages, runner]
import ./toy_profile

let root = getTempDir() / "shpg-runner-" & $getCurrentProcessId()
let fixture = root / "fixture"
let work = root / "work"

proc makeFixture() =
  removeDir(root)
  createDir(fixture / "sub")
  writeFile(fixture / "a.txt", "alpha\n")
  writeFile(fixture / "sub" / "_gitignore", "x\n")

proc exampleOf(page: string): Example =
  let ex = examplesOf(parsePage(page), toy)
  doAssert ex.errors.len == 0 and ex.examples.len == 1
  ex.examples[0]

suite "runner":
  # SPEC: SHPG-RUN-01
  test "SHPG-RUN-01 Given a fixture, when copied, then _gitignore becomes .gitignore and a .git directory exists":
    makeFixture()
    copyFixture(fixture, work)
    check fileExists(work / "sub" / ".gitignore")
    check not fileExists(work / "sub" / "_gitignore")
    check dirExists(work / ".git")
    check readFile(work / "a.txt") == "alpha\n"

  # SPEC: SHPG-RUN-02
  test "SHPG-RUN-02 Given a command, when run, then output, error and status are kept apart under the fixed environment":
    makeFixture()
    copyFixture(fixture, work)
    let r = run(work, "echo $LC_ALL $TZ $NO_COLOR $TERM $PAGER; echo e >&2; wc -c; exit 2")
    check r.stdout.startsWith("C.UTF-8 UTC 1 dumb cat\n")
    check r.stderr == "e\n"
    check r.exitCode == 2
    check "0" in r.stdout.splitLines[1]

  # SPEC: SHPG-RUN-03
  test "SHPG-RUN-03 Given examples, when checked, then a matching one passes and a differing output or status fails":
    makeFixture()
    let good = exampleOf("# T\n## Why\n```sh\ncat a.txt\n```\n```text\nalpha\n```\n")
    check checkExample(fixture, work, good).ok
    let wrongOut = exampleOf("# T\n## Why\n```sh\ncat a.txt\n```\n```text\nbeta\n```\n")
    check not checkExample(fixture, work, wrongOut).ok
    let wrongExit = exampleOf("# T\n## Why\n```sh\n# exit: 1\ncat a.txt\n```\n```text\nalpha\n```\n")
    check "exit 0, expected 1" in checkExample(fixture, work, wrongExit).message

  # SPEC: SHPG-RUN-03
  test "SHPG-RUN-03 Given an idempotent example, when the second run changes the tree, then it fails":
    makeFixture()
    let stable = exampleOf("# T\n## Why\n```sh idempotent\nmkdir -p d\n```\n```text\n```\n")
    check checkExample(fixture, work, stable).ok
    let drift = exampleOf("# T\n## Why\n```sh idempotent\necho x >> log\n```\n```text\n```\n")
    check "second run changed the tree" in checkExample(fixture, work, drift).message
