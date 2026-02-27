
# Introduction {-}

Introduction should answer the following questions, ideally in this order:

1. What is the nature of the problem the thesis is addressing?
1. What is the common approach for solving that problem now?
1. How this thesis approaches the problem?
1. What are the results? Did something improve?
1. What can the reader expect in the individual chapters of the thesis?

Expected length of the introduction is between 1--4 pages. Longer introductions may require sub-sectioning with appropriate headings --- use `{-}` at the end of the headline to avoid numbering (with section names like 'Motivation' and 'Related work'), but try to avoid lengthy discussion of anything specific. Any "real science" (definitions, theorems, methods, data) should go into other chapters.
More parameters in curly braces can be combined with space.

\todo{You may notice that this paragraph briefly shows different "types" of 'quotes' in \TeX/markdown, and the usage difference between a hyphen (-), en-dash (--) and em-dash (---).}

## Subsection with custom link (`\label` in \LaTeX) {- #chap:test}

It is very advisable to skim through a book about scientific English writing before starting the thesis. I can recommend '\citetitle{glasman2010science}' by @glasman2010science.

## Markdown basic citation syntax {-}

- `@glasman2010science` -- author name → @glasman2010science
- `[-@glasman2010science]` -- publication year → [-@glasman2010science]
- `[@glasman2010science]` -- only bracket with numer → [@glasman2010science]

Style rendering of citations can be changed in `citation.lua` filter. Additionally, you can use \LaTeX{} macros like `\citetitle` for printing book name.
