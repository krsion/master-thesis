# Implementation repository {#chap:appendix-repo}

The mydenicek implementation evaluated in this thesis is maintained as a separate Git repository.

**Repository.** <https://github.com/krsion/mydenicek>

**Evaluated revision.** Commit [`94158789`](https://github.com/krsion/mydenicek/commit/94158789b841a2bdc30eddd3c0e29458c44d834a) is the revision against which all measurements, formative tests, and property-based tests reported in this thesis were produced.

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

The full suite on the evaluated revision passes with 304 tests across 22 files (unit, property-based, and formative), including two 5-peer convergence test suites with 1000 fuzzing runs each.

**Running the demos locally.**

```
deno task sync-server    # start the relay server on ws://localhost:8080
deno task mywebnicek:dev # start the web app on http://localhost:5173
```

Deployed instances of the server and web app (used to reproduce the Playwright browser tests) are described in [@Sec:hosting]. The live demo is at <https://krsion.github.io/mydenicek>.

**Thesis repository.** The Markdown-plus-LaTeX source of this thesis is at <https://github.com/krsion/master-thesis>.
