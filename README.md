# arc_example

A tiny JavaScript **bundler written in Gleam**, built on [Arc](https://github.com/alii/arc)'s
composable module APIs — **no JS runtime involved**. It takes a real multi-module
app from `app/` (relative imports, directory indexes, `node_modules`, re-exports)
and emits a single browser-ready `dist/bundle.js`.

```sh
gleam run     # bundles app/main.mjs → dist/bundle.js + dist/index.html
gleam test
node dist/bundle.js   # or open dist/index.html in a browser
```

## The Arc APIs this demonstrates

Arc's module pipeline is layered so you can stop at whichever stage you need.
A bundler uses the first three and never touches the compiler or VM:

| layer | call | gives you |
|---|---|---|
| parse | `parser.parse(source, parser.Module)` | `ast.Program` (ESTree-shaped AST) |
| static ESM semantics | `esm.analyze(program)` | imports, exports, requested specifiers — the spec's ImportEntries / ExportEntries / ModuleRequests |
| graph | `graph.load(entry, source, resolve_and_load)` | the full transitive `SourceGraph`: every module's source, AST, summary, and raw→resolved specifier map, in dependency-first order |
| compile + run | `module.compile_bundle`, `arc/engine` | bytecode + execution (not used here) |

The runtime's own `module.compile_bundle` is built on the same `graph.load`,
so a bundler and Arc's evaluator walk graphs with identical resolution
semantics — this isn't a parallel "lite" code path.

```toml
[dependencies]
arc = { git = "https://github.com/alii/arc.git", ref = "master" }
```

### The whole frontend is one call

```gleam
import arc/module/graph

graph.load("app/main.mjs", source, resolver.resolve, resolver.load)
// -> Result(SourceGraph, GraphError)
```

The two callbacks are yours (the same split as Rollup's `resolveId`/`load`):

```gleam
resolve: fn(request: esm.ModuleRequest, referrer: String) -> Result(resolved_id, String)
load:    fn(resolved_id: String) -> Result(source, String)
```

`resolve` runs once per import edge — `request.specifier` is the raw text as
written (the request also carries the import phase, and will carry import
attributes when those land), and the string you return IS the module's
identity: ten different relative spellings that resolve to the same id are
one module. `load` then runs **exactly once per unique module**, so source
is never read or parsed twice no matter how many importers point at it. Arc
deliberately doesn't impose resolution semantics — specifiers can be paths,
URLs, or anything else.

## What's in this repo

- **`src/arc_example/resolver.gleam`** — real disk resolution, the part Arc
  leaves to the host: `./`/`../` relative to the importer, extension probing
  (`.mjs`, `.js`), directory `index.*`, and bare specifiers via `node_modules`
  walk-up reading `package.json` `"module"`/`"main"`.
- **`src/arc_example/bundler.gleam`** — the "last mile": emits one IIFE with a
  module registry + require cache. All import/export rewrites are *generated
  from Arc's static analysis* (`ImportBinding`s, `ExportEntry`s, the specifier
  map); the only textual edit to module source is dropping/unwrapping the
  top-level `import`/`export` lines.
- **`app/`** — the demo app being bundled. Exercises extensionless imports,
  directory indexes, `export * from`, named re-exports, default + namespace +
  named imports, and a fake `left-pad` in `node_modules`.

## Honest limitations

These are demo simplifications, not Arc limitations — except the first one:

- **No character spans on AST nodes (yet)** — Arc's AST has statement-level
  line numbers only, so the bundler rewrites at line granularity:
  `import`/`export` declarations must sit on their own single line. Expression
  spans would unlock exact rewriting (and better diagnostics).
- Exported `let` reassignment isn't live across module boundaries (exports are
  snapshotted after each module body runs); cyclic graphs load but get CommonJS
  cycle semantics, not ESM live bindings. Arc's *runtime* does implement real
  live bindings + TDZ — that fidelity just isn't reproduced by this little
  emitter.
- `import defer` is treated as an eager namespace import.
- No `package.json` `"exports"` maps, conditions, or source maps.
- The parser currently uses Erlang FFI (unicode/regex tables), so Erlang
  target only — fine for dev tooling on the BEAM.
