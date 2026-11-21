## Running an example in a fresh copy of a fixture tree under a fixed environment.
## With container.nim, the only module that touches the file system and starts processes.

import std/[algorithm, options, os, osproc, strtabs, strutils, times]
import ./pages

type
  RunResult* = object
    stdout*: string
    stderr*: string
    exitCode*: int

  RunRoutine* = proc (work, command: string): RunResult {.closure, raises: [OSError, IOError].}
    ## Runs `command` with `work` as its working directory: `run` here, `runInContainer` in
    ## container.nim through a closure that fixes the image and capabilities.

  Outcome* = object
    ok*: bool
    message*: string  ## why it failed, with the expected and actual output

const
  timedOutExitCode* = 1001
    ## The status of a run stopped at its time limit. A process status is 0..255, so no real
    ## run has it.
  defaultTimeoutMs* = 120_000
    ## The time limit of one run when the caller gives none: long enough for any example,
    ## short enough that a command or a podman that never ends does not stall a test run.

proc runBounded*(program: string; args: openArray[string]; workDir: string; env: StringTableRef;
    timeoutMs: int): RunResult {.raises: [OSError, IOError].} =
  ## program with args in workDir under env, standard input empty. Standard output and error go
  ## to files, not pipes, so any amount of either comes back whole and kept apart. A run still
  ## going after timeoutMs is killed and has status timedOutExitCode, with `timed out` on
  ## standard error after what it printed.
  let io = getTempDir() / ("shpg-run-" & $getCurrentProcessId() & "-" &
    $int64(epochTime() * 1_000_000))
  removeDir(io)
  createDir(io)
  defer: removeDir(io)
  let outPath = io / "out"
  let errPath = io / "err"
  # The file names go in as positional parameters, so env stays exactly what the caller gave.
  var shArgs = @["-c", "o=$1; e=$2; shift 2; exec \"$@\" </dev/null >\"$o\" 2>\"$e\"", "sh",
    outPath, errPath, program]
  for a in args: shArgs.add a
  let p = startProcess("/bin/sh", workingDir = workDir, args = shArgs, env = env, options = {})
  defer: p.close()
  var timedOut = false
  try:
    # waitForExit(timeout) kills the process itself on timeout and reports 137, which a command
    # can also end with; poll instead, so that a timeout is known as one.
    let deadline = epochTime() + timeoutMs.float / 1000.0
    var status = p.peekExitCode()
    while status == -1 and epochTime() < deadline:
      sleep(20)
      status = p.peekExitCode()
    if status == -1:
      timedOut = true
      p.kill()
      status = p.waitForExit()
    result.exitCode = status
  except IOError as e:
    raise e
  except OSError as e:
    raise e
  except CatchableError as e:
    raise newException(IOError, "waiting for " & program & ": " & e.msg)
  result.stdout = (if fileExists(outPath): readFile(outPath) else: "")
  result.stderr = (if fileExists(errPath): readFile(errPath) else: "")
  if timedOut:
    result.exitCode = timedOutExitCode
    result.stderr.add "timed out after " & $timeoutMs & " ms\n"

proc resetDir*(dir: string) {.raises: [OSError, IOError].} =
  ## dir exists and is empty afterwards. An existing dir is emptied, not removed and made again:
  ## a container runtime that shares host directories into a virtual machine (podman machine on
  ## macOS) can keep the removed directory mounted, and the next run then sees no directory.
  if not dirExists(dir):
    createDir(dir)
    return
  for kind, path in walkDir(dir):
    if kind == pcDir:
      removeDir(path)
    else:
      removeFile(path)

proc copyFixture*(fixture, dest: string) {.raises: [OSError, IOError].} =
  ## dest becomes a copy of fixture with every `_gitignore` renamed `.gitignore` and an empty
  ## `.git` directory at the root, so that tools that look for a repository root treat it as one.
  ## dest itself is kept (resetDir), only its content is replaced.
  resetDir(dest)
  copyDirWithPermissions(fixture, dest)
  for f in walkDirRec(dest, yieldFilter = {pcFile}):
    if f.extractFilename == "_gitignore":
      moveFile(f, f.parentDir / ".gitignore")
  createDir(dest / ".git")
  createDir(dest / ".home")

proc fixedEnv(work: string): StringTableRef {.raises: [].} =
  result = newStringTable(modeCaseSensitive)
  result["PATH"] = getEnv("PATH")
  result["HOME"] = work / ".home"
  result["XDG_CONFIG_HOME"] = work / ".home" / ".config"
  result["LC_ALL"] = "C.UTF-8"
  result["TZ"] = "UTC"
  result["NO_COLOR"] = "1"
  result["TERM"] = "dumb"
  result["PAGER"] = "cat"
  result["BAT_PAGER"] = ""

proc run*(work, command: string; timeoutMs = defaultTimeoutMs): RunResult
    {.raises: [OSError, IOError].} =
  ## `sh -c command` in work with empty standard input; standard output and error kept apart,
  ## the status returned; stopped at timeoutMs as runBounded says.
  # Standard input is /dev/null, as for a command started from cron or CI: rg and others search
  # standard input when it is a pipe or a file and no path is given.
  runBounded("/bin/sh", ["-c", "exec </dev/null\n" & command], work, fixedEnv(work), timeoutMs)

proc snapshot*(dir: string): seq[(string, string)] {.raises: [OSError, IOError].} =
  ## Every file under dir (relative path, content), sorted; `.home` excluded.
  for f in walkDirRec(dir, yieldFilter = {pcFile}, relative = true):
    if f.startsWith(".home"): continue
    result.add (f, readFile(dir / f))
  result.sort()

proc freshCopy(fixture, base: string): string {.raises: [OSError, IOError].} =
  ## A copy of fixture in a directory under base that no earlier run has used. A container
  ## runtime that shares host directories into a virtual machine (podman machine on macOS) can
  ## keep a stale view of a path that was emptied or made again, so every run gets a new path.
  createDir(base)
  var n = int64(epochTime() * 1_000_000)
  while dirExists(base / ("run-" & $n)): inc n
  result = base / ("run-" & $n)
  copyFixture(fixture, result)

proc check1(work, fixture: string; cmd: CodeBlock; ex: Example; label: string;
    runCmd: RunRoutine): Outcome {.raises: [OSError, IOError].} =
  let dir = freshCopy(fixture, work)
  defer: removeDir(dir)
  let r = runCmd(dir, cmd.body)
  if r.exitCode != ex.exitCode:
    return Outcome(ok: false, message: label & " line " & $cmd.line & ": exit " & $r.exitCode &
      ", expected " & $ex.exitCode & "\nstderr:\n" & r.stderr)
  if r.stdout != ex.expected:
    return Outcome(ok: false, message: label & " line " & $cmd.line &
      ": output differs\n--- expected\n" & ex.expected & "--- actual\n" & r.stdout &
      "--- stderr\n" & r.stderr)
  Outcome(ok: true, message: "")

proc checkExampleWith*(fixture, work: string; ex: Example; runCmd: RunRoutine): Outcome
    {.raises: [OSError, IOError].} =
  ## One example: its output, its status, its classic counterpart and its
  ## idempotence, every command run by runCmd. Each run gets a fresh copy of fixture in a new
  ## directory under work (freshCopy); the two idempotence runs share one copy.
  result = check1(work, fixture, ex.command, ex, "command", runCmd)
  if not result.ok: return
  if ex.classic.isSome:
    result = check1(work, fixture, ex.classic.get, ex, "classic", runCmd)
    if not result.ok: return
  if ex.idempotent:
    let dir = freshCopy(fixture, work)
    defer: removeDir(dir)
    let first = runCmd(dir, ex.command.body)
    if first.exitCode != ex.exitCode:
      return Outcome(ok: false, message: "idempotent line " & $ex.command.line &
        ": first run exit " & $first.exitCode)
    let once = snapshot(dir)
    let second = runCmd(dir, ex.command.body)
    if second.exitCode != ex.exitCode:
      return Outcome(ok: false, message: "idempotent line " & $ex.command.line &
        ": second run exit " & $second.exitCode)
    if snapshot(dir) != once:
      return Outcome(ok: false, message: "idempotent line " & $ex.command.line &
        ": a second run changed the tree")
  result = Outcome(ok: true, message: "")

proc checkExample*(fixture, work: string; ex: Example): Outcome {.raises: [OSError, IOError].} =
  ## checkExampleWith the local `run`.
  let local: RunRoutine = proc (w, command: string): RunResult {.closure, raises: [OSError, IOError].} =
    run(w, command)
  checkExampleWith(fixture, work, ex, local)
