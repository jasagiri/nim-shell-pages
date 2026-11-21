## Running a command inside a podman container (SHPG-CONTAINER-01…08): for pages whose commands
## need a system the host does not have (another distribution, root, a network namespace). Same
## `RunResult` as runner.run.
##
## Why a refusal is a value and not an exception: a caller that asks for a capability off the
## allowlist has made a mistake it can read and fix, as with a failed example (runner.Outcome);
## an exception is kept for what the caller cannot know in advance (podman missing, a pipe
## failing), as in runner.run.

import std/[os, osproc, streams, strutils]
import ./runner

const
  allowedCaps* = ["NET_RAW", "NET_ADMIN", "SYS_ADMIN"]
    ## The only capabilities a page may ask for. Never `--privileged`, never `ALL`.
  refusedExitCode* = 1000
    ## The status of a refused request. A process status is 0..255, so no real run has it.
  fixedContainerEnv = [("LC_ALL", "C.UTF-8"), ("TZ", "UTC"), ("NO_COLOR", "1"), ("TERM", "dumb"),
    ("PAGER", "cat"), ("HOME", "/work")]
    ## The same variables as runner.fixedEnv; the paths inside the container are fixed.

func refusedCaps*(caps: openArray[string]): seq[string] {.raises: [].} =
  ## The entries of caps that are not on the allowlist, in order.
  for c in caps:
    if c notin allowedCaps: result.add c

func refusal(message: string): RunResult {.raises: [].} =
  RunResult(stdout: "", stderr: "refused: " & message & "\n", exitCode: refusedExitCode)

proc runInContainer*(image, work, command: string; caps: openArray[string]): RunResult
    {.raises: [OSError, IOError].} =
  ## `podman run --rm --network none` with work mounted at /work, the fixed environment, one
  ## `--cap-add` per entry of caps, and `/bin/sh -c command` with empty standard input; standard
  ## output and error kept apart, the status returned. A request podman would misread is
  ## answered with refusedExitCode and the reason on stderr, and podman is not started: a
  ## capability off the allowlist, an empty image or one starting with `-`, a work directory
  ## with `:` or `,` in it (they split the volume option).
  let bad = refusedCaps(caps)
  if bad.len > 0:
    return refusal("capability not on the allowlist (" & allowedCaps.join(" ") & "): " &
      bad.join(" "))
  if image.len == 0 or image.startsWith("-"):
    return refusal("image name `" & image & "`")
  if work.len == 0 or work.contains({':', ','}):
    return refusal("work directory `" & work & "` is empty or contains `:` or `,`")
  let hostWork = (if work.isAbsolute: work else: getCurrentDir() / work)
  var args = @["run", "--rm", "--network", "none", "-v", hostWork & ":/work:Z",
    "-w", "/work"]
  for (key, value) in fixedContainerEnv:
    args.add "-e"
    args.add key & "=" & value
  for c in caps:
    args.add "--cap-add"
    args.add c
  args.add image
  args.add "/bin/sh"
  args.add "-c"
  args.add "exec </dev/null\n" & command
  let p = startProcess("podman", args = args, options = {poUsePath})
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
    raise newException(IOError, "reading the container's output: " & e.msg)
