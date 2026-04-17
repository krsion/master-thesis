# Implementation repository {#chap:appendix-repo}

The mydenicek implementation evaluated in this thesis is maintained as a separate Git repository.

**Repository.** `https://github.com/krsion/mydenicek-core`

**Evaluated revision.** Commit `3c62f5852e07c262ce7ee8eeddf2322f179f82e9` is the revision against which all measurements, formative tests, and property-based tests reported in this thesis were produced.

**Contents.**

- `packages/core/` --- the core CRDT engine (event graph, edits, selector rewriting, materialization). All theorems and invariants in [@Chap:implementation] refer to code in this package.
- `packages/server/` --- the WebSocket relay server.
- `packages/web-app/` --- the React single-page application used for the web demos referenced in [@Chap:formative].
- `packages/core/tests/` --- unit, property-based, and formative tests.

**Build and test.** The project uses Deno 2.x. After cloning, run:

```
deno task check     # type-check + lint across workspace
deno task test      # run all tests
```

The full suite on the evaluated revision passes with 212 tests across 15 files (unit, property-based, and formative).

**Running the demos locally.**

```
deno task server    # start the relay server on ws://localhost:8080
deno task web       # start the web app on http://localhost:5173
```

Deployed instances of the server and web app (used to reproduce the Playwright browser tests) are at `https://mydenicek-server.fly.dev` and `https://mydenicek.fly.dev` respectively.

**Thesis repository.** The Markdown-plus-LaTeX source of this thesis is at `https://github.com/krsion/master-thesis`. The revision matching the submitted text is `86a0d0281da3b912a73ba8dfeac6bf671ad5cd37`.
