## E tests for docs/specification.md SHPG-RUN-01…04: running an example in a fresh copy of a
## fixture tree under the fixed environment.

import std/[os, strutils, times, unittest]
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

  # SPEC: SHPG-RUN-01
  test "SHPG-RUN-01 Given a used work directory, when the fixture is copied again, then the directory is kept and only its content is replaced":
    makeFixture()
    copyFixture(fixture, work)
    writeFile(work / "left.txt", "x")
    createDir(work / "made" / "deep")
    let before = getFileInfo(work).id
    copyFixture(fixture, work)
    check getFileInfo(work).id == before
    check not fileExists(work / "left.txt")
    check not dirExists(work / "made")
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

var ranCommands: seq[string]  ## outside the work tree, which the idempotence check compares

proc fakeRun(work, command: string): RunResult {.raises: [OSError, IOError].} =
  ## A runner that does not start a process: it answers `fake` and records the command, so a
  ## test can tell which routine ran.
  ranCommands.add command.strip
  RunResult(stdout: "fake\n", stderr: "", exitCode: 0)

suite "runner with another run routine":
  # SPEC: SHPG-RUN-04
  test "SHPG-RUN-04 Given a run routine, when an example is checked with it, then the routine decides the output and the local run is not used":
    makeFixture()
    let viaFake = exampleOf("# T\n## Why\n```sh\ncat a.txt\n```\n```text\nfake\n```\n")
    check checkExampleWith(fixture, work, viaFake, fakeRun).ok
    check not checkExample(fixture, work, viaFake).ok
    let local = exampleOf("# T\n## Why\n```sh\ncat a.txt\n```\n```text\nalpha\n```\n")
    check not checkExampleWith(fixture, work, local, fakeRun).ok

  # SPEC: SHPG-RUN-04
  test "SHPG-RUN-04 Given a classic pair and an idempotent example, when checked with a routine, then every run goes through it":
    makeFixture()
    ranCommands = @[]
    let pair = exampleOf("# T\n## Why\n```sh classic\nls\n```\n```sh idempotent\nmkdir -p d\n```\n```text\nfake\n```\n")
    check checkExampleWith(fixture, work, pair, fakeRun).ok
    check ranCommands == @["mkdir -p d", "ls", "mkdir -p d", "mkdir -p d"]

  # SPEC: SHPG-RUN-04
  test "SHPG-RUN-04 Given a closure that holds its own settings, when an example is checked with it, then the settings reach the command":
    makeFixture()
    let suffix = "!"
    let withSuffix = proc (w, command: string): RunResult {.closure, raises: [OSError, IOError].} =
      RunResult(stdout: command.strip & suffix & "\n", stderr: "", exitCode: 0)
    let ex = exampleOf("# T\n## Why\n```sh\nhello\n```\n```text\nhello!\n```\n")
    check checkExampleWith(fixture, work, ex, withSuffix).ok

suite "bounded runs":
  # SPEC: SHPG-RUN-05
  test "SHPG-RUN-05 Given a command that does not end, when its time limit passes, then it is stopped with timedOutExitCode":
    let w = getTempDir() / "shpg-run05-" & $getCurrentProcessId()
    createDir(w)
    defer: removeDir(w)
    let started = epochTime()
    let r = run(w, "echo begun; sleep 30", timeoutMs = 500)
    check r.exitCode == timedOutExitCode
    check r.stdout == "begun\n"
    check "timed out" in r.stderr
    check epochTime() - started < 10.0
    check run(w, "exit 137").exitCode == 137

  # SPEC: SHPG-RUN-05
  test "SHPG-RUN-05 Given more output than a pipe holds on both streams, when run, then all of it comes back":
    let w = getTempDir() / "shpg-run05b-" & $getCurrentProcessId()
    createDir(w)
    defer: removeDir(w)
    let r = run(w, "head -c 300000 /dev/zero | tr '\\0' e >&2; head -c 300000 /dev/zero | tr '\\0' o")
    check r.exitCode == 0
    check r.stdout.len == 300000
    check r.stderr.len == 300000
