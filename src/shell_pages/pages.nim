## Reading a details page: its sections, its fenced blocks and the examples they form
##. Pure: the page arrives as a string, so the same page always gives the same
## examples or the same errors. Running the examples is the runner's job (runner.nim).
##
## Block info strings:
##   ```sh             a command, run in a fresh copy of the fixture; the next block must be ```text
##   ```sh idempotent  the same, and running it twice leaves the tree as running it once does
##   ```sh classic     the classic counterpart; the next blocks must be ```sh and ```text, and both
##                     commands must print that text
##   ```sh bad         a wrong form (a pitfall), never run; the next blocks must be the fix and its
##                     ```text
##   ```sh unverified  not run (a tool that is not installed, interactive, or prints what differs
##                     per machine); allowed only on a page whose status line says why
##   ```text           the exact standard output of the command before it
## A command may start with header comment lines, in any order: `# exit: N` (it must end with
## status N; every other command ends with 0) and `# spec: <prefix>-<TOOL>-NN ...` (the spec IDs
## of the page's spec table that this example confirms; the prefix is the profile's).

import std/[options, sequtils, strutils]
import ./profile

type
  BlockKind* = enum
    bkRun, bkIdempotent, bkClassic, bkBad, bkUnverified, bkText, bkOther

  CodeBlock* = object
    kind*: BlockKind
    info*: string  ## the whole info string after the fence
    body*: string  ## the lines between the fences, each ending in "\n"
    line*: int     ## 1-based line of the opening fence

  Example* = object
    classic*: Option[CodeBlock]  ## the classic command that must print the same text
    command*: CodeBlock
    expected*: string
    exitCode*: int
    idempotent*: bool
    specs*: seq[string]  ## the IDs of its `# spec:` header lines

  Section* = object
    heading*: string
    body*: string

  Page* = object
    title*: string
    status*: string  ## the reason after "Status: 未検証", or "" for a verified page
    sections*: seq[Section]
    blocks*: seq[CodeBlock]

  PageError* = object
    line*: int
    message*: string

  Examples* = object
    examples*: seq[Example]
    errors*: seq[PageError]

const
  statusPrefix = "Status: 未検証"
  exitPrefix = "# exit:"
  specPrefix* = "# spec:"

func kindOf(info: string): BlockKind {.raises: [].} =
  let words = info.splitWhitespace
  if words.len == 0: return bkOther
  case words[0]
  of "text": bkText
  of "sh":
    if words.len == 1: bkRun
    else:
      case words[1]
      of "idempotent": bkIdempotent
      of "classic": bkClassic
      of "bad": bkBad
      of "unverified": bkUnverified
      else: bkOther
  else: bkOther

func parsePage*(text: string): Page {.raises: [].} =
  ## Title (the first `# ` line), status line, `## ` sections in order, and every fenced block.
  ## A fence is a line starting with ``` outside a block; the block ends at the next line that
  ## is exactly ```.
  var inBlock = false
  var current = CodeBlock()
  var lineNo = 0
  for raw in text.splitLines:
    inc lineNo
    if inBlock:
      if raw == "```":
        result.blocks.add current
        if result.sections.len > 0:
          result.sections[^1].body.add raw & "\n"
        inBlock = false
      else:
        current.body.add raw & "\n"
        if result.sections.len > 0:
          result.sections[^1].body.add raw & "\n"
      continue
    if raw.startsWith("```"):
      let info = raw[3 .. ^1].strip
      current = CodeBlock(kind: kindOf(info), info: info, body: "", line: lineNo)
      inBlock = true
      if result.sections.len > 0:
        result.sections[^1].body.add raw & "\n"
    elif raw.startsWith("## "):
      result.sections.add Section(heading: raw[3 .. ^1].strip, body: "")
    elif raw.startsWith("# ") and result.title.len == 0:
      result.title = raw[2 .. ^1].strip
    elif raw.startsWith(statusPrefix) and result.sections.len == 0:
      result.status = raw[statusPrefix.len .. ^1].strip(chars = {' ', '(', ')', ':'})
    elif result.sections.len > 0:
      result.sections[^1].body.add raw & "\n"

func isSpecId(w: string; profile: PageProfile): bool {.raises: [].} =
  ## <prefix>-<TOOL>-NN: TOOL is upper-case letters and digits, NN two digits.
  let parts = w.split('-')
  if parts.len != 3 or parts[0] != profile.specIdPrefix or parts[1].len == 0 or
      parts[2].len != 2: return false
  parts[1].allCharsInSet({'A'..'Z', '0'..'9'}) and parts[2].allCharsInSet({'0'..'9'})

type Header = object
  exit: Option[int]
  specs: seq[string]
  error: string  ## "" when the header is well formed

func readHeader(body: string; profile: PageProfile): Header {.raises: [].} =
  ## The leading `# exit: N` (N in 0..255) and `# spec: ID ...` lines of a command, in any order.
  ## Without an exit line the status is 0.
  result.exit = some(0)
  var sawExit = false
  for line in body.splitLines:
    if line.startsWith(exitPrefix):
      let digits = line[exitPrefix.len .. ^1].strip
      var n = 0
      var ok = digits.len in 1 .. 3 and not sawExit
      for c in digits:
        if c notin {'0'..'9'}: ok = false
        else: n = n * 10 + (ord(c) - ord('0'))
      if not ok or n > 255:
        return Header(exit: none(int), error: "malformed `# exit: N` line (N in 0..255)")
      result.exit = some(n)
      sawExit = true
    elif line.startsWith(specPrefix):
      let ids = line[specPrefix.len .. ^1].splitWhitespace
      if ids.len == 0 or not ids.allIt(isSpecId(it, profile)):
        return Header(exit: result.exit, error: "malformed `# spec:` line (IDs like " &
          profile.specIdPrefix & "-TOOL-NN separated by spaces)")
      for id in ids:
        if id notin result.specs: result.specs.add id
    else:
      break

func withoutHeader*(body: string): string {.raises: [].} =
  ## The command without its leading `# exit:` and `# spec:` lines.
  var rest = body
  while rest.startsWith(exitPrefix) or rest.startsWith(specPrefix):
    let nl = rest.find('\n')
    rest = (if nl < 0: "" else: rest[nl + 1 .. ^1])
  rest

func examplesOf*(page: Page; profile: PageProfile): Examples {.raises: [].} =
  ## Pairs the blocks into examples, or says at which line the page breaks the block rules.
  let b = page.blocks
  var i = 0
  template fail(at: int; msg: string) =
    result.errors.add PageError(line: at, message: msg)

  func isCommand(k: BlockKind): bool = k in {bkRun, bkIdempotent}

  while i < b.len:
    let k = b[i].kind
    case k
    of bkRun, bkIdempotent:
      if page.status.len > 0:
        fail(b[i].line, "a page marked 未検証 has only ```sh unverified commands")
        i += (if i + 1 < b.len and b[i + 1].kind == bkText: 2 else: 1)
        continue
      if i + 1 >= b.len or b[i + 1].kind != bkText:
        fail(b[i].line, "```sh must be followed by its ```text output")
        inc i
        continue
      let h = readHeader(b[i].body, profile)
      if h.error.len > 0:
        fail(b[i].line, h.error)
      else:
        result.examples.add Example(classic: none(CodeBlock), command: b[i],
          expected: b[i + 1].body, exitCode: h.exit.get, idempotent: k == bkIdempotent, specs: h.specs)
      i += 2
    of bkClassic, bkBad:
      let what = (if k == bkClassic: "```sh classic" else: "```sh bad")
      if i + 2 >= b.len or not isCommand(b[i + 1].kind) or b[i + 2].kind != bkText:
        fail(b[i].line, what & " must be followed by a ```sh command and its ```text output")
        inc i
        continue
      let h = readHeader(b[i + 1].body, profile)
      if h.error.len > 0:
        fail(b[i + 1].line, h.error)
      else:
        result.examples.add Example(
          classic: (if k == bkClassic: some(b[i]) else: none(CodeBlock)),
          command: b[i + 1], expected: b[i + 2].body, exitCode: h.exit.get,
          idempotent: b[i + 1].kind == bkIdempotent, specs: h.specs)
      i += 3
    of bkUnverified:
      if page.status.len == 0:
        fail(b[i].line, "```sh unverified needs a status line `Status: 未検証 (<reason>)`")
      inc i
    of bkText:
      fail(b[i].line, "```text without a command before it")
      inc i
    of bkOther:
      inc i

func sectionOrderErrors*(page: Page; profile: PageProfile): seq[string] {.raises: [].} =
  ## The required sections missing or out of order; empty when the page follows the shape.
  var at = 0
  for want in profile.requiredSections:
    var found = -1
    for j in at ..< page.sections.len:
      if page.sections[j].heading == want:
        found = j
        break
    if found < 0: result.add "missing or out of order: ## " & want
    else: at = found + 1
