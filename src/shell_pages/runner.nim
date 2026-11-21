## Running an example in a fresh copy of a fixture tree under a fixed environment.
## With container.nim, the only module that touches the file system and starts processes.

import std/[algorithm, options, os, osproc, streams, strtabs, strutils]
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

proc copyFixture*(fixture, dest: string) {.raises: [OSError, IOError].} =
  ## dest becomes a copy of fixture with every `_gitignore` renamed `.gitignore` and an empty
  ## `.git` directory at the root, so that tools that look for a repository root treat it as one.
  removeDir(dest)
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

proc run*(work, command: string): RunResult {.raises: [OSError, IOError].} =
  ## `sh -c command` in work with empty standard input; standard output and error kept apart,
  ## the status returned.
  # Standard input is /dev/null, as for a command started from cron or CI: rg and others search
  # standard input when it is a pipe or a file and no path is given.
  let p = startProcess("/bin/sh", workingDir = work, args = ["-c", "exec </dev/null\n" & command],
    env = fixedEnv(work), options = {})
  defer: p.close()
  try:
    p.inputStream.close()
    result.stdout = p.outputStream.readAll()
    result.stderr = p.errorStream.readAll()
    result.exitCode = p.waitForExit()
  except IOError as e:
    raise e
  except OSError as e:
    raise e
  except CatchableError as e:
    raise newException(IOError, "reading the command's output: " & e.msg)

proc snapshot*(dir: string): seq[(string, string)] {.raises: [OSError, IOError].} =
  ## Every file under dir (relative path, content), sorted; `.home` excluded.
  for f in walkDirRec(dir, yieldFilter = {pcFile}, relative = true):
    if f.startsWith(".home"): continue
    result.add (f, readFile(dir / f))
  result.sort()

proc check1(work, fixture: string; cmd: CodeBlock; ex: Example; label: string;
    runCmd: RunRoutine): Outcome {.raises: [OSError, IOError].} =
  copyFixture(fixture, work)
  let r = runCmd(work, cmd.body)
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
  ## idempotence, every command run by runCmd. work is removed and recreated for every run.
  result = check1(work, fixture, ex.command, ex, "command", runCmd)
  if not result.ok: return
  if ex.classic.isSome:
    result = check1(work, fixture, ex.classic.get, ex, "classic", runCmd)
    if not result.ok: return
  if ex.idempotent:
    copyFixture(fixture, work)
    let first = runCmd(work, ex.command.body)
    if first.exitCode != ex.exitCode:
      return Outcome(ok: false, message: "idempotent line " & $ex.command.line &
        ": first run exit " & $first.exitCode)
    let once = snapshot(work)
    let second = runCmd(work, ex.command.body)
    if second.exitCode != ex.exitCode:
      return Outcome(ok: false, message: "idempotent line " & $ex.command.line &
        ": second run exit " & $second.exitCode)
    if snapshot(work) != once:
      return Outcome(ok: false, message: "idempotent line " & $ex.command.line &
        ": a second run changed the tree")
  result = Outcome(ok: true, message: "")

proc checkExample*(fixture, work: string; ex: Example): Outcome {.raises: [OSError, IOError].} =
  ## checkExampleWith the local `run`.
  checkExampleWith(fixture, work, ex, run)
