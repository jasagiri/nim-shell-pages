## E tests for docs/specification.md SHPG-PROFILE-01…05: every repository-specific value of the
## parser, the spec-table check and the dataset derivation comes from the PageProfile.

import std/[json, strutils, unittest]
import shell_pages/[dataset, pages, spec]
import ./toy_profile

const page = """# Tool: qq
## Why
Because.
## Usage
- first
- second
```sh
# spec: ZZ-QQ-01
echo a
```
```text
a
```
## Gotchas
- keep
## Refs
Catalog: 0123456789abcdef.
"""

const table = """| ID | 箇所 | 主張 | 確かめ |
|---|---|---|---|
| ZZ-QQ-01 | U1 | one | 例 |
| ZZ-QQ-02 | U2 | two | 本文のみ (alpha: reason) |
| ZZ-QQ-03 | G1 | keep | 本文のみ (beta: reason) |
"""

const datasetPage = """# Find: qq
## Why
Why text.
## Usage
- hidden
## Gotchas
In scripts.
## Refs
Catalog: 0123456789abcdef.
"""

suite "profile: sections":
  # SPEC: SHPG-PROFILE-01
  test "SHPG-PROFILE-01 Given a profile with other section names, when a page is checked, then those names are required in order":
    check sectionOrderErrors(parsePage(page), toy).len == 0
    check sectionOrderErrors(parsePage(page.replace("## Refs", "## Sources")), toy) ==
      @["missing or out of order: ## Refs"]
    check sectionOrderErrors(parsePage("# T\n## Intent\nx\n"), toy).len == 4

suite "profile: spec ids":
  # SPEC: SHPG-PROFILE-02
  test "SHPG-PROFILE-02 Given a profile prefix, when a spec line is read, then only that prefix is an ID":
    let ok = examplesOf(parsePage(page), toy)
    check ok.errors.len == 0
    check ok.examples[0].specs == @["ZZ-QQ-01"]
    let other = examplesOf(parsePage(page.replace("ZZ-QQ-01", "CLI-QQ-01")), toy)
    check other.errors.len == 1
    check "ZZ-TOOL-NN" in other.errors[0].message

  # SPEC: SHPG-PROFILE-03
  test "SHPG-PROFILE-03 Given a profile with other letters and categories, when a table is checked, then they decide":
    check specErrors(parsePage(page), toy, table).len == 0
    check specErrors(parsePage(page), toy, table.replace("(beta:", "(機械:")).len == 1
    check specErrors(parsePage(page), toy, table.replace("U2", "D2")).len >= 1
    check specErrors(parsePage(page), toy, table.replace("| G1 |", "| K1 |")).len >= 1
    check specErrors(parsePage(page), toy, table.replace("ZZ-QQ-03", "CLI-QQ-03")).len == 1
    let uncovered = specErrors(parsePage(page), toy,
      table.replace("| ZZ-QQ-03 | G1 | keep | 本文のみ (beta: reason) |\n", ""))
    check uncovered.len == 1
    check uncovered[0].startsWith("G1:")
    check "Gotchas" in uncovered[0]

suite "profile: dataset":
  # SPEC: SHPG-PROFILE-04
  test "SHPG-PROFILE-04 Given a profile, when a page is derived, then IDs, areas, spec IDs and texts are the profile's":
    let rs = recordsOf(toy, "qq.md", datasetPage)
    check rs.len == 2
    check rs[0].id == "explain:zed/qq"
    check rs[0].instruction == "Find: qq (explain?)"
    check rs[0].output == "Why text.\n\n- hidden"
    check rs[0].specIds == @["T-PAGE"]
    check rs[0].files == @["pages/zz/qq.md"]
    check rs[0].sources == @["0123456789abcdef"]
    check rs[1].id == "gotcha:zed/qq"
    check rs[1].kind == "gotcha"
    check rs[1].instruction == "Gotchas of qq?"
    check rs[1].output == "In scripts."
    check toJson(toy, rs[0])["area"].getStr == "zed"
    let chat = toChat(toy, rs[0])
    check chat["messages"][0]["content"].getStr == "toy system"

  # SPEC: SHPG-PROFILE-04
  test "SHPG-PROFILE-04 Given examples of each kind, when derived, then their spec IDs and instructions are the profile's":
    let full = datasetPage.replace("## Gotchas", """```sh
echo plain
```
```text
plain
```
```sh idempotent
mkdir -p d
```
```text
```
```sh classic
printf 'x\n'
```
```sh
echo x
```
```text
x
```
```sh bad
echo (
```
```sh
echo fixed
```
```text
fixed
```
## Gotchas""")
    let rs = recordsOf(toy, "qq.md", full)
    var seen: seq[string]
    for r in rs: seen.add r.kind
    check seen == @["explain", "gotcha", "task", "rewrite", "pitfall"]
    check rs[2].instruction == "- hidden"  # the nearest prose line above the block
    for r in rs[2 .. 4]:
      check r.specIds[0] == "T-EX"
    check rs[3].specIds == @["T-EX", "T-CLASSIC"]
    check rs[3].instruction == "Rewrite with qq now."
    check "Usage notes:\n- hidden" in rs[3].output
    check rs[4].instruction == "Mend it."

  # SPEC: SHPG-PROFILE-05
  test "SHPG-PROFILE-05 Given an idempotent example, when derived, then the profile's idempotence ID is added":
    let p = "# Find: qq\n## Why\nw\n## Usage\n- u\nMake a dir:\n```sh idempotent\nmkdir -p d\n```\n```text\n```\n## Gotchas\ng\n## Refs\nNone.\n"
    let rs = recordsOf(toy, "qq.md", p)
    check rs.len == 3
    check rs[2].kind == "task"
    check rs[2].specIds == @["T-EX", "T-IDEM"]
