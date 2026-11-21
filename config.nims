# Development tasks (`nim <task>`); listed at the end of `nim help`.
#
#   nim test    every tests/test_*.nim
#
# Not a nimble task: `test` clashes with nimble's built-in command, and nimble would resolve
# dependencies. The package builds no executables. The container tests need podman.

import std/[algorithm, os, strutils]

proc testFiles(): seq[string] =
  for f in listFiles("tests"):
    let name = f.extractFilename
    if name.startsWith("test_") and name.endsWith(".nim"): result.add f
  result.sort()

task test, "all tests":
  for t in testFiles():
    echo "== " & t
    exec "nim c -r --hints:off " & t

task specCoverage, "G1 table":
  exec "../nim-spec-coverage/bin/tools/spec_coverage . --spec-table docs/specification.md" &
    " > docs/quality/g1-spec-coverage.md"
