# Implementation repository {#chap:appendix-repo}

The mydenicek implementation evaluated in this thesis is maintained as a separate Git repository.

**Repository.** `https://github.com/krsion/mydenicek`

**Evaluated revision.** Commit `8503e788968ccaa5cf4e95eadab4b50d124adafd` is the revision against which all measurements, formative tests, and property-based tests reported in this thesis were produced.

**Contents.**

- `packages/core/` --- the core CRDT engine (event graph, edits, selector rewriting, materialization). All theorems and invariants in [@Chap:implementation] refer to code in this package.
- `packages/sync/` --- the WebSocket relay server library.
- `apps/mywebnicek/` --- the React single-page application used for the web demos referenced in [@Chap:formative].
- `apps/sync-server/` --- the deployed sync server.
- `packages/core/tests/` --- unit, property-based, and formative tests.

**Build and test.** The project uses Deno 2.x. After cloning, run:

```
deno task check     # type-check + lint across workspace
deno task test      # run all tests
```

The full suite on the evaluated revision passes with 246 tests across 23 files (unit, property-based, and formative), including two 5-peer convergence test suites with 1000 fuzzing runs each.

**Running the demos locally.**

```
deno task sync-server    # start the relay server on ws://localhost:8080
deno task mywebnicek:dev # start the web app on http://localhost:5173
```

Deployed instances of the server and web app (used to reproduce the Playwright browser tests) are described in [@Sec:hosting]. The live demo is at `https://krsion.github.io/mydenicek`.

**Thesis repository.** The Markdown-plus-LaTeX source of this thesis is at `https://github.com/krsion/master-thesis`. The revision matching the submitted text is `77b2d1dcb387ea9a9f1ed2420dcce14cc6121e72`.
