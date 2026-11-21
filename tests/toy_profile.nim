## A profile that shares no value with any real repository, so that a test fails when the package
## still reads a literal instead of the profile.

import shell_pages/profile

const toy* = PageProfile(
  requiredSections: @["Why", "Usage", "Gotchas", "Refs"],
  introHeading: "Why",
  differencesHeading: "Usage",
  keepHeading: "Gotchas",
  sourcesHeading: "Refs",
  differencesLetter: 'U',
  keepLetter: 'G',
  specIdPrefix: "ZZ",
  textOnlyCategories: @["alpha", "beta"],
  pagesDir: "pages/zz/",
  area: "zed",
  systemMessage: "toy system",
  pageSpecId: "T-PAGE",
  exampleSpecId: "T-EX",
  classicSpecId: "T-CLASSIC",
  idempotentSpecId: "T-IDEM",
  keepKind: "gotcha",
  explainQuestion: " (explain?)",
  keepPrefix: "Gotchas of ",
  keepSuffix: "?",
  rewritePrefix: "Rewrite with ",
  rewriteSuffix: " now.",
  pitfallRequest: "Mend it.",
  differsLabel: "Usage notes:")
