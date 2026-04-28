# Implementation repository {#chap:appendix-repo}

The mydenicek implementation evaluated in this thesis is maintained as a separate Git repository and published on JSR.

**Repository.** <https://github.com/krsion/mydenicek>

**Published packages.** [`@mydenicek/core@0.5.0`](https://jsr.io/@mydenicek/core) and [`@mydenicek/sync@0.1.4`](https://jsr.io/@mydenicek/sync).

**Evaluated revision.** Commit [`532bdf90`](https://github.com/krsion/mydenicek/commit/532bdf90) is the revision against which all measurements, tests, and benchmarks reported in this thesis were produced.

**Contents.**

- `packages/core/` --- the core CRDT engine (event graph, edits, selector rewriting, materialization). The complexity analysis in [@Sec:complexity] refers to code in this package.
- `packages/sync/` --- the WebSocket relay server library.
- `packages/react/` --- React bindings for the core CRDT.
- `apps/mywebnicek/` --- the React single-page application used for the web demos referenced in [@Sec:formative-examples].
- `apps/sync-server/` --- the deployed sync server.
- `packages/core/tests/` and `packages/sync/tests/` --- unit, property-based, and formative tests.

**Build and test.** The project uses Deno 2.x. After cloning, run:

```
deno task check     # type-check + lint across workspace
deno task test      # run all tests
```

The full suite on the evaluated revision passes with 358 tests across 28 files (unit, integration, property-based, and formative), including two 5-peer convergence test suites with 1000 fuzzing runs each. Branch coverage is 90% for the core package.

**Running the demos locally.**

```
deno task sync-server    # relay server (ws://localhost:8080)
deno task mywebnicek:dev # web app (http://localhost:5173)
```

The live demo is at <https://krsion.github.io/mydenicek>.

**Thesis repository.** The Markdown-plus-LaTeX source of this thesis is at <https://github.com/krsion/master-thesis>.