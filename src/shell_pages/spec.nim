## The spec table of a details page and its check against the page.
## Pure: both arrive as strings.
##
## A table has the columns `| ID | 箇所 | 主張 | 確かめ |`, one row per claim:
##   ID    <prefix>-<TOOL>-NN, TOOL being the tool of the page title (`# Find files by name: fd` -> FD)
##   箇所  <D><n> = the n-th bullet of the profile's differences section, <K><n> = the n-th bullet of
##         its keep section; every bullet is pointed at by at least one row
##   確かめ `例` when an example of the page names the ID in a `# spec:` line, or
##         `本文のみ (<category>: <reason>)` when none does. The category is one of the profile's
##         `textOnlyCategories`. Text-only IDs leave G1's denominator.

import std/[sets, strutils]
import ./[pages, profile]

type
  SpecRow* = object
    id*, where*, statement*, check*: string
    line*: int

  SpecTable* = object
    rows*: seq[SpecRow]
    errors*: seq[string]

const
  textOnly* = "本文のみ ("

func cells(line: string): seq[string] {.raises: [].} =
  ## The cells of a table row; `\|` is a bar inside a cell.
  var cur = ""
  var i = 0
  let l = line.strip
  var started = false
  while i < l.len:
    if l[i] == '\\' and i + 1 < l.len and l[i + 1] == '|':
      cur.add '|'
      inc i, 2
      continue
    if l[i] == '|':
      if started: result.add cur.strip
      started = true
      cur = ""
    else:
      cur.add l[i]
    inc i
  # the text after the last bar is not a cell

func parseSpecTable*(text: string): SpecTable {.raises: [].} =
  ## The rows of the table whose header is `| ID | 箇所 | 主張 | 確かめ |`; malformed rows are errors.
  var inTable = false
  var lineNo = 0
  for raw in text.splitLines:
    inc lineNo
    let line = raw.strip
    if not line.startsWith("|"):
      continue
    let c = cells(line)
    if c.len == 4 and c[0] == "ID":
      inTable = true
      continue
    if not inTable or (c.len > 0 and c[0].startsWith("---")): continue
    if c.len != 4:
      result.errors.add "line " & $lineNo & ": a row needs 4 cells (ID, 箇所, 主張, 確かめ)"
    else:
      result.rows.add SpecRow(id: c[0], where: c[1], statement: c[2], check: c[3], line: lineNo)

func toolOf(page: Page): string {.raises: [].} =
  ## The upper-cased tool of the title (`# Find files by name: fd` -> FD); "" when the part after
  ## the colon is not a single word (a page about several tools), and then the table picks the
  ## name, the same for all its rows.
  let i = page.title.rfind(": ")
  let name = (if i < 0: page.title else: page.title[i + 2 .. ^1]).strip
  if name.len == 0 or not name.allCharsInSet(Letters + Digits): return ""
  name.toUpperAscii

func bulletCount(page: Page; heading: string): int {.raises: [].} =
  ## Lines starting with "- " outside fenced blocks, in the named section.
  for s in page.sections:
    if s.heading != heading: continue
    var fenced = false
    for l in s.body.splitLines:
      if l.startsWith("```"): fenced = not fenced
      elif not fenced and l.startsWith("- "): inc result

func parseWhere(w: string; letter: char): int {.raises: [].} =
  ## n of "D<n>" / "K<n>", or 0 when w is not of that form.
  if w.len < 2 or w[0] != letter: return 0
  for ch in w[1 .. ^1]:
    if ch notin {'0'..'9'}: return 0
    result = result * 10 + (ord(ch) - ord('0'))

func specErrors*(page: Page; profile: PageProfile; tableText: string): seq[string] {.raises: [].} =
  ## What is wrong between the page and its table; empty when they agree.
  let t = parseSpecTable(tableText)
  result.add t.errors
  let claimed = examplesOf(page, profile).examples
  var named = initHashSet[string]()
  for ex in claimed:
    for id in ex.specs: named.incl id
  var tool = toolOf(page)
  if tool.len == 0 and t.rows.len > 0:
    let parts = t.rows[0].id.split('-')
    if parts.len == 3: tool = parts[1]
  let prefix = profile.specIdPrefix & "-" & tool & "-"
  var seen = initHashSet[string]()
  var tableIds = initHashSet[string]()
  let nD = bulletCount(page, profile.differencesHeading)
  let nK = bulletCount(page, profile.keepHeading)
  var coveredD, coveredK = initHashSet[int]()
  for r in t.rows:
    tableIds.incl r.id
    if not r.id.startsWith(prefix) or r.id.len != prefix.len + 2:
      result.add r.id & ": the ID must be " & prefix & "NN for this page"
    if r.id in seen: result.add r.id & ": listed twice"
    seen.incl r.id
    let d = parseWhere(r.where, profile.differencesLetter)
    let k = parseWhere(r.where, profile.keepLetter)
    if d in 1 .. nD: coveredD.incl d
    elif k in 1 .. nK: coveredK.incl k
    else:
      result.add r.id & ": 箇所 " & r.where & " points at no bullet (" & $nD & " in " & profile.differencesHeading &
        ", " & $nK & " in " & profile.keepHeading & ")"
    if r.statement.len == 0: result.add r.id & ": the claim is empty"
    if r.check == "例":
      if r.id notin named: result.add r.id & ": marked 例 but no example names it in a `# spec:` line"
    elif r.check.startsWith(textOnly) and r.check.endsWith(")"):
      let reason = r.check[textOnly.len .. ^2].strip
      let colon = reason.find(':')
      let category = (if colon < 0: "" else: reason[0 ..< colon])
      let why = (if colon < 0: reason else: reason[colon + 1 .. ^1].strip)
      if why.len == 0:
        result.add r.id & ": 本文のみ needs a reason"
      elif category notin profile.textOnlyCategories:
        result.add r.id & ": 本文のみ needs a category, one of " & profile.textOnlyCategories.join(" ") &
          ", then \": \" and the reason"
      if r.id in named: result.add r.id & ": marked 本文のみ but an example names it"
    else:
      result.add r.id & ": 確かめ must be 例 or 本文のみ (<category>: <reason>)"
  for id in named:
    if id notin tableIds: result.add id & ": named by an example but not in the table"
  for i in 1 .. nD:
    if i notin coveredD: result.add $profile.differencesLetter & $i & ": no row points at this bullet of " &
      profile.differencesHeading
  for i in 1 .. nK:
    if i notin coveredK: result.add $profile.keepLetter & $i & ": no row points at this bullet of " &
      profile.keepHeading
