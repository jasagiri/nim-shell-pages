## E tests for docs/specification.md SHPG-CONTAINER-01…06: running a command inside a podman
## container. Needs podman and the image below (pulled on first use).

import std/[os, strutils, unittest]
import shell_pages/[container, runner]

const image = "docker.io/library/ubuntu:24.04"
let work = getTempDir() / "shpg-container-" & $getCurrentProcessId()

proc fresh(): string =
  removeDir(work)
  createDir(work)
  work

suite "container":
  # SPEC: SHPG-CONTAINER-01
  test "SHPG-CONTAINER-01 Given a command, when run in the container, then its standard output and status come back":
    let r = runInContainer(image, fresh(), "echo hello; echo oops >&2; exit 3", [])
    check r.stdout == "hello\n"
    check r.stderr.contains("oops")
    check r.exitCode == 3

  # SPEC: SHPG-CONTAINER-02
  test "SHPG-CONTAINER-02 Given the fixed environment, when the container prints it, then each variable has its value":
    let r = runInContainer(image, fresh(),
      "echo $LC_ALL $TZ $NO_COLOR $TERM $PAGER $HOME; pwd", [])
    check r.stdout == "C.UTF-8 UTC 1 dumb cat /work\n/work\n"
    check r.exitCode == 0

  # SPEC: SHPG-CONTAINER-03
  test "SHPG-CONTAINER-03 Given standard input, when the command reads it, then it is empty":
    let r = runInContainer(image, fresh(), "wc -c", [])
    check r.stdout.strip == "0"

  # SPEC: SHPG-CONTAINER-04
  test "SHPG-CONTAINER-04 Given the work directory, when the command writes in it, then the files are visible on the host":
    let w = fresh()
    let r = runInContainer(image, w, "echo data > out.txt", [])
    check r.exitCode == 0
    check readFile(w / "out.txt") == "data\n"

  # SPEC: SHPG-CONTAINER-05
  test "SHPG-CONTAINER-05 Given no capability, when the command opens a network, then there is only loopback":
    let r = runInContainer(image, fresh(), "ls /sys/class/net", [])
    check r.stdout.strip == "lo"

  # SPEC: SHPG-CONTAINER-06
  test "SHPG-CONTAINER-06 Given an allowed capability, when the container runs, then it holds one it does not hold by default":
    # SYS_ADMIN is not in podman's default set, so the effective set differs only when asked for.
    let plain = runInContainer(image, fresh(), "grep CapEff /proc/self/status", [])
    let admin = runInContainer(image, fresh(), "grep CapEff /proc/self/status", ["SYS_ADMIN"])
    check plain.exitCode == 0
    check admin.exitCode == 0
    check plain.stdout != admin.stdout

  # SPEC: SHPG-CONTAINER-07
  test "SHPG-CONTAINER-07 Given a capability off the allowlist, when asked for, then it is refused before podman runs":
    for caps in [@["SYS_PTRACE"], @["NET_RAW", "ALL"], @["--privileged"], @["net_raw"], @[""]]:
      let w = fresh()
      let r = runInContainer(image, w, "touch ran", caps)
      check r.exitCode == refusedExitCode
      check r.stdout == ""
      check "refused" in r.stderr
      check not fileExists(w / "ran")
    check refusedCaps(["NET_RAW", "ALL", "NET_ADMIN", "x"]) == @["ALL", "x"]
    check refusedCaps(["NET_RAW", "NET_ADMIN", "SYS_ADMIN"]).len == 0

  # SPEC: SHPG-CONTAINER-08
  test "SHPG-CONTAINER-08 Given an image or directory podman would misread, when asked for, then it is refused":
    check runInContainer("", fresh(), "true", []).exitCode == refusedExitCode
    check runInContainer("--privileged", fresh(), "true", []).exitCode == refusedExitCode
    check runInContainer(image, "a:b", "true", []).exitCode == refusedExitCode
    check runInContainer(image, "a,b", "true", []).exitCode == refusedExitCode
