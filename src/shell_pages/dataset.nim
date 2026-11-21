## Deriving training records from the details pages. Pure: pages arrive as
## (name, text) pairs, so the same pages give the same bytes. Pages marked 未検証 give no record.
## Every repository-specific string comes from the PageProfile.

import std/[algorithm, json, options, strutils]
import ./[pages, profile]

type
  Record* = object
    id*, kind*, topic*, instruction*, input*, output*: string
    specIds*, sources*, files*: seq[string]

func withoutSpecLines(text: string): string {.raises: [].} =
  ## The `# spec:` header lines name claims of the spec table; they are not part of a command
  ## that a record shows.
  var kept: seq[string]
  for l in text.splitLines:
    if not l.startsWith(specPrefix): kept.add l
  kept.join("\n")

func sectionBody(page: Page; heading: string): string {.raises: [].} =
  for s in page.sections:
    if s.heading == heading: return withoutSpecLines(s.body.strip)
  ""

func sourceIds(page: Page; profile: PageProfile): seq[string] {.raises: [].} =
  let body = sectionBody(page, profile.sourcesHeading)
  for w in body.multiReplace((",", " "), (".", " "), (";", " "), ("`", " ")).splitWhitespace:
    if w.len == 16 and w.allCharsInSet(HexDigits) and w notin result: result.add w

func proseBefore(lines: seq[string]; fenceLine: int): string {.raises: [].} =
  ## The last prose line above the block that opens at fenceLine (1-based), skipping blank lines;
  ## "" when the nearest non-blank line closes another block or is a heading.
  var i = fenceLine - 2
  while i >= 0 and lines[i].strip.len == 0: dec i
  if i < 0: return ""
  let l = lines[i].strip
  if l.startsWith("```") or l.startsWith("#"): "" else: l

func answer(ex: Example): string {.raises: [].} =
  result = "```sh\n" & withoutHeader(ex.command.body) & "```\n\nOutput:\n```text\n" & ex.expected & "```"
  if ex.exitCode != 0: result.add "\n\nExit status: " & $ex.exitCode

func tool(page: Page): string {.raises: [].} =
  let i = page.title.rfind(": ")
  if i < 0: page.title else: page.title[i + 2 .. ^1]

func pad2(n: int): string {.raises: [].} = (if n < 10: "0" & $n else: $n)

func recordsOf*(profile: PageProfile; name, text: string): seq[Record] {.raises: [].} =
  ## The records of one page; none for a page marked 未検証.
  let page = parsePage(text)
  if page.status.len > 0: return @[]
  let topic = name.replace(".md", "")
  let lines = text.splitLines
  let sources = sourceIds(page, profile)
  let file = profile.pagesDir & name
  result.add Record(id: "explain:" & profile.area & "/" & topic, kind: "explain", topic: topic,
    instruction: page.title & profile.explainQuestion,
    input: "", output: sectionBody(page, profile.introHeading) & "\n\n" &
      sectionBody(page, profile.differencesHeading),
    specIds: @[profile.pageSpecId], sources: sources, files: @[file])
  result.add Record(id: profile.keepKind & ":" & profile.area & "/" & topic, kind: profile.keepKind, topic: topic,
    instruction: profile.keepPrefix & tool(page) & profile.keepSuffix,
    input: "", output: sectionBody(page, profile.keepHeading),
    specIds: @[profile.pageSpecId], sources: sources, files: @[file])
  var nTask, nRewrite, nPitfall = 0
  let blocks = page.blocks
  for ex in examplesOf(page, profile).examples:
    let at = file & ":" & $ex.command.line
    # The block before the command says what kind of example it is.
    var prev = -1
    for j, b in blocks:
      if b.line == ex.command.line: prev = j - 1
    let isBad = prev >= 0 and blocks[prev].kind == bkBad
    if ex.classic.isSome:
      inc nRewrite
      result.add Record(id: "rewrite:" & profile.area & "/" & topic & "#" & pad2(nRewrite), kind: "rewrite", topic: topic,
        instruction: profile.rewritePrefix & tool(page) & profile.rewriteSuffix,
        input: "```sh\n" & withoutHeader(ex.classic.get.body) & "```",
        output: answer(ex) & "\n\n" & profile.differsLabel & "\n" &
          sectionBody(page, profile.differencesHeading),
        specIds: @[profile.exampleSpecId, profile.classicSpecId] & ex.specs, sources: sources,
        files: @[file & ":" & $ex.classic.get.line, at])
    elif isBad:
      inc nPitfall
      let why = proseBefore(lines, blocks[prev].line)
      result.add Record(id: "pitfall:" & profile.area & "/" & topic & "#" & pad2(nPitfall), kind: "pitfall", topic: topic,
        instruction: profile.pitfallRequest & (if why.len > 0: " (" & why & ")" else: ""),
        input: "```sh\n" & blocks[prev].body & "```", output: answer(ex),
        specIds: @[profile.exampleSpecId] & ex.specs, sources: sources, files: @[file & ":" & $blocks[prev].line, at])
    else:
      let what = proseBefore(lines, ex.command.line)
      if what.len == 0: continue
      inc nTask
      result.add Record(id: "task:" & profile.area & "/" & topic & "#" & pad2(nTask), kind: "task", topic: topic,
        instruction: what, input: "", output: answer(ex),
        specIds: (if ex.idempotent: @[profile.exampleSpecId, profile.idempotentSpecId]
          else: @[profile.exampleSpecId]) & ex.specs,
        sources: sources, files: @[at])

func toJson*(profile: PageProfile; r: Record): JsonNode {.raises: [].} =
  %*{"id": r.id, "kind": r.kind, "area": profile.area, "concept": r.topic, "instruction": r.instruction,
     "input": r.input, "output": r.output, "specIds": r.specIds, "sources": r.sources, "files": r.files}

func toChat*(profile: PageProfile; r: Record): JsonNode {.raises: [].} =
  let user = (if r.input.len > 0: r.instruction & "\n\n" & r.input else: r.instruction)
  %*{"id": r.id, "messages": [
    {"role": "system", "content": profile.systemMessage},
    {"role": "user", "content": user},
    {"role": "assistant", "content": r.output}]}

func render*(profile: PageProfile; pagesIn: openArray[(string, string)]): (string, string) {.raises: [].} =
  ## (records.jsonl, chat.jsonl) for the given pages, sorted by id.
  var all: seq[Record]
  for (name, text) in pagesIn: all.add recordsOf(profile, name, text)
  all.sort(proc (a, b: Record): int = cmp(a.id, b.id))
  for r in all:
    result[0].add $toJson(profile, r) & "\n"
    result[1].add $toChat(profile, r) & "\n"
