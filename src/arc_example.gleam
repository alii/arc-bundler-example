//// Bundle `app/main.mjs` into `dist/bundle.js` using Arc's composable
//// module APIs — parser + static ESM analysis + graph walk, no JS runtime
//// involved. Run with: gleam run

import arc/esm
import arc/module/graph
import arc/parser
import arc_example/bundler
import arc_example/resolver
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

const entry = "app/main.mjs"

pub fn main() -> Nil {
  case run() {
    Ok(Nil) -> Nil
    Error(message) -> io.println_error("error: " <> message)
  }
}

fn run() -> Result(Nil, String) {
  use #(entry_id, entry_source) <- result.try(resolver.load_entry(entry))

  // The whole frontend is one call: Arc parses every module, extracts the
  // import/export metadata, and walks the graph; our resolver (disk lookup)
  // decides what specifiers mean.
  use g <- result.try(
    graph.load(entry_id, entry_source, resolver.resolve, resolver.load)
    |> result.map_error(describe_graph_error),
  )

  io.println("module graph (dependencies first):")
  list.each(g.order, fn(specifier) {
    case dict.get(g.modules, specifier) {
      Ok(module) -> {
        io.println("  " <> summary_line(module))
        list.each(graph.dependencies(module), fn(dep) {
          io.println("    ← " <> dep)
        })
      }
      Error(Nil) -> io.println("  " <> specifier <> " (missing from graph?!)")
    }
  })

  let output = bundler.bundle(g)
  use Nil <- result.try(write_dist("dist/bundle.js", output))
  use Nil <- result.try(write_dist("dist/index.html", index_html()))

  io.println("")
  io.println(
    "wrote dist/bundle.js ("
    <> int.to_string(string.byte_size(output))
    <> " bytes, "
    <> int.to_string(dict.size(g.modules))
    <> " modules)",
  )
  io.println(
    "wrote dist/index.html — open it in a browser, or: node dist/bundle.js",
  )
  Ok(Nil)
}

fn describe_graph_error(error: graph.GraphError) -> String {
  case error {
    graph.ParseFailed(specifier, parse_error) ->
      "SyntaxError in "
      <> specifier
      <> " (offset "
      <> int.to_string(parser.parse_error_pos(parse_error))
      <> "): "
      <> parser.parse_error_to_string(parse_error)
    graph.ResolveFailed(raw, referrer, message) ->
      "cannot resolve '" <> raw <> "' from " <> referrer <> ": " <> message
    graph.LoadFailed(specifier, message) ->
      "cannot load " <> specifier <> ": " <> message
    graph.SourcePhaseUnsupported(specifier) ->
      specifier
      <> " uses 'import source', which the bundler does not support yet"
  }
}

fn summary_line(module: graph.SourceModule) -> String {
  module.specifier
  <> " ("
  <> int.to_string(list.length(graph.dependencies(module)))
  <> " deps, exports: "
  <> string.join(exported_names(module), ", ")
  <> ")"
}

/// Human-readable exported names off Arc's ExportEntries.
fn exported_names(module: graph.SourceModule) -> List(String) {
  list.map(module.summary.exports, fn(export) {
    case export {
      esm.LocalExport(export_name:, ..) -> export_name
      esm.ReExport(export_name:, ..) -> export_name
      esm.ReExportAll(source_specifier:) -> "* from " <> source_specifier
      esm.ReExportNamespace(export_name:, ..) -> export_name
    }
  })
}

fn write_dist(path: String, contents: String) -> Result(Nil, String) {
  use Nil <- result.try(
    simplifile.create_directory_all("dist")
    |> result.map_error(fn(err) {
      "creating dist/: " <> simplifile.describe_error(err)
    }),
  )
  simplifile.write(path, contents)
  |> result.map_error(fn(err) { path <> ": " <> simplifile.describe_error(err) })
}

fn index_html() -> String {
  string.join(
    [
      "<!doctype html>",
      "<html>",
      "<head>",
      "  <meta charset=\"utf-8\" />",
      "  <title>bundled by arc</title>",
      "</head>",
      "<body>",
      "  <pre id=\"app\"></pre>",
      "  <script src=\"bundle.js\"></script>",
      "</body>",
      "</html>",
      "",
    ],
    "\n",
  )
}
