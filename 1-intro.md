
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
- `[-@glasman2010science]` -- publication year (in `authoryear-comp` style or it's same as syntax lower) → [-@glasman2010science]
- `[@glasman2010science]` -- only bracket with numer → [@glasman2010science]

Other examples of syntax:

- [see page 34 @glasman2010science; or 64 @lamport1994latex; or 65 @lamport1994latex]
- [@glasman2010science, pp. iv, vi-xi, (xv)-(xvii) with suffix here]

Additionally, you can use \LaTeX{} macros like `\citetitle` for printing book name.

## Cross-referencing {- #chap:refs}

For cross-referencing in Markdown, the citation syntax is used; when a colon `:` appears in the citation, it is interpreted as a reference to something in the text. For example, `[@chap:refs]` will be replaced by "Section 1.2" (or whatever the section number is) and will link to the section with label `chap:refs`. You can also use `\cref{chap:refs}` or `\Cref{chap:refs}` in \LaTeX{} for the same purpose.

Examples:
- `[@chap:refs]` is translated to `\cref{chap:refs}` and it will produce: [@chap:refs]
- `[@Chap:refs]` (note the first letter is capital) is translated to `\Cref{chap:refs}` and it will produce: [@Chap:refs]
- Of course, you can create references to more things like `[@Fig:f;@Fig:g]` will produce: [@Fig:f;@Fig:g]
    - The capitalization of the first letter matters only for the first reference. The output of the `[@Fig:f;@fig:g]` will be the same as `[@Fig:f;@Fig:g]`

This is done by custom lua filter `crossref-gen.lua`.