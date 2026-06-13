//// Real disk module resolution — the part Arc deliberately does NOT do for
//// you. Arc's module graph walker asks a host callback what each specifier
//// means; this module is an example implementation of that callback:
////
////   - `./x`, `../x`  → resolved against the importing module's directory
////   - extensionless  → probes `.mjs`, `.js`
////   - directories    → probes `index.mjs`, `index.js`
////   - bare (`foo`)   → walks up looking for `node_modules/foo`, reading
////                      `package.json` `"module"` / `"main"` if present
////
//// A module's identity (its key in the graph) is its normalized path from
//// the project root, so the same file reached via different specifiers
//// dedupes to one module.

import arc/esm
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

/// Load the entry module directly (it has no parent to resolve against).
pub fn load_entry(path: String) -> Result(#(String, String), String) {
  let id = normalize(path)
  use source <- result.map(load(id))
  #(id, source)
}

/// `graph.load`'s Resolve callback: a ModuleRequest (raw specifier + phase,
/// later attributes) and the importing module's id → the resolved id.
/// Probes the filesystem for existence but never reads file contents —
/// that's `load`, which Arc calls once per unique module.
pub fn resolve(
  request: esm.ModuleRequest,
  referrer: String,
) -> Result(String, String) {
  locate(request.specifier, referrer)
}

/// `graph.load`'s Load callback: resolved id → source text.
pub fn load(specifier: String) -> Result(String, String) {
  read(specifier)
}

/// Disk lookup: raw specifier + referrer id → resolved id.
fn locate(raw: String, parent: String) -> Result(String, String) {
  case raw {
    "./" <> _rest | "../" <> _rest -> probe(join(dirname(parent), raw), raw)
    "/" <> _rest -> probe(normalize(raw), raw)
    _bare -> resolve_bare(dirname(parent), raw)
  }
}

// --- file probing ------------------------------------------------------------

/// Try the path as written, then with extensions, then as a directory index.
fn probe(path: String, raw: String) -> Result(String, String) {
  let candidates = [
    path,
    path <> ".mjs",
    path <> ".js",
    join(path, "index.mjs"),
    join(path, "index.js"),
  ]
  case list.find(candidates, is_file) {
    Ok(found) -> Ok(found)
    Error(Nil) ->
      Error(
        "cannot resolve '"
        <> raw
        <> "': tried "
        <> string.join(candidates, ", "),
      )
  }
}

// --- bare specifiers (node_modules) -------------------------------------------

/// Walk up from `dir` looking for `node_modules/<name>`.
fn resolve_bare(dir: String, name: String) -> Result(String, String) {
  let pkg_dir = join(join(dir, "node_modules"), name)
  case is_directory(pkg_dir) {
    True -> load_package(pkg_dir, name)
    False ->
      case dir {
        "" | "." | "/" ->
          Error("cannot resolve bare specifier '" <> name <> "': no node_modules contains it")
        _ -> resolve_bare(dirname(dir), name)
      }
  }
}

/// Entry point of a package directory: `package.json` `"module"`, falling
/// back to `"main"`, falling back to index probing.
fn load_package(pkg_dir: String, name: String) -> Result(String, String) {
  let manifest = join(pkg_dir, "package.json")
  let entry = case is_file(manifest) {
    True -> {
      use content <- result.map(read(manifest))
      package_entry(content, manifest)
    }
    False -> Ok("index.mjs")
  }
  use entry <- result.try(entry)
  probe(join(pkg_dir, entry), name)
}

/// Extract `"module"` ?? `"main"` ?? "index.mjs" from package.json contents.
fn package_entry(content: String, manifest: String) -> String {
  let decoder = {
    use module_field <- decode.optional_field(
      "module",
      None,
      decode.optional(decode.string),
    )
    use main_field <- decode.optional_field(
      "main",
      None,
      decode.optional(decode.string),
    )
    decode.success(option.or(module_field, main_field))
  }
  case json.parse(content, decoder) {
    Ok(Some(entry)) -> entry
    Ok(None) -> "index.mjs"
    Error(err) -> {
      io.println_error(
        "warning: unparseable " <> manifest <> ": " <> string.inspect(err),
      )
      "index.mjs"
    }
  }
}

// --- tiny path library --------------------------------------------------------

fn read(path: String) -> Result(String, String) {
  simplifile.read(path)
  |> result.map_error(fn(err) {
    path <> ": " <> simplifile.describe_error(err)
  })
}

fn is_file(path: String) -> Bool {
  simplifile.is_file(path) |> result.unwrap(False)
}

fn is_directory(path: String) -> Bool {
  simplifile.is_directory(path) |> result.unwrap(False)
}

fn dirname(path: String) -> String {
  case list.reverse(string.split(path, "/")) {
    [_file, ..rest] -> string.join(list.reverse(rest), "/")
    [] -> ""
  }
}

fn join(a: String, b: String) -> String {
  normalize(a <> "/" <> b)
}

/// Collapse `.`, `..` and empty segments. Preserves a leading `/`.
pub fn normalize(path: String) -> String {
  let absolute = string.starts_with(path, "/")
  let segments =
    string.split(path, "/")
    |> list.fold([], fn(acc, segment) {
      case segment {
        "" | "." -> acc
        ".." ->
          case acc {
            [] | ["..", ..] -> ["..", ..acc]
            [_popped, ..rest] -> rest
          }
        _ -> [segment, ..acc]
      }
    })
    |> list.reverse
    |> string.join("/")
  case absolute {
    True -> "/" <> segments
    False -> segments
  }
}
