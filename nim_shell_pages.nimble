# Package
version       = "0.1.0"
author        = "jasagiri"
description   = "Shared machinery for repositories of tested command-line pages: page parser, spec-table check, dataset derivation, and runners (local and in a podman container) for the examples"
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]

# Dependencies
requires "nim >= 2.4.2"

task test, "Run the test suite":
  exec "nim test"
