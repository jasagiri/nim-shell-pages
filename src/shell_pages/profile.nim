## What differs between the repositories that share this package (SHPG-PROFILE-01): one value,
## passed to the parser, the spec-table check and the dataset derivation. The package keeps no
## global state and knows no repository by name.

type
  PageProfile* = object
    ## Section names are matched against `## ` headings exactly.
    requiredSections*: seq[string]  ## the headings every page has, in this order
    introHeading*: string           ## the section whose text opens an `explain` record
    differencesHeading*: string     ## the section whose bullets the spec table points at with
                                    ## `differencesLetter`; also the tail of a `rewrite` answer
    keepHeading*: string            ## the section whose bullets the spec table points at with
                                    ## `keepLetter`; also the answer of a `keep` record
    sourcesHeading*: string         ## the section whose 16-hex-digit words are catalog IDs
    differencesLetter*, keepLetter*: char  ## `D` and `K`: 箇所 cells read `D<n>` and `K<n>`
    specIdPrefix*: string           ## spec IDs are `<prefix>-<TOOL>-NN`; no `-` in it
    textOnlyCategories*: seq[string]  ## the categories a `本文のみ (<category>: <reason>)` may name
    pagesDir*: string               ## where the pages live, relative to the repository root
    area*: string                   ## the `area` of a JSON record, and the `<area>` of a record ID
    systemMessage*: string          ## the system turn of every chat triple
    pageSpecId*: string             ## written into the `explain` and `keep` records
    exampleSpecId*: string          ## written into every example record
    classicSpecId*: string          ## also written into `rewrite` records
    idempotentSpecId*: string       ## also written into idempotent `task` records
    keepKind*: string               ## the `kind` of the record that answers `keepHeading`
    explainQuestion*: string        ## `<title>` + this is the instruction of an `explain` record
    keepPrefix*, keepSuffix*: string  ## the instruction of a `keep` record is prefix + tool + suffix
    rewritePrefix*, rewriteSuffix*: string  ## likewise for `rewrite` records
    pitfallRequest*: string         ## the instruction of a `pitfall` record, before its hint
    differsLabel*: string           ## the heading above the differences in a `rewrite` answer
