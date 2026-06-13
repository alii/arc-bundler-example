// Entry module. Exercises: extensionless relative imports, directory-index
// imports, namespace imports, bare specifiers from node_modules.
import { greet } from "./components/greeting";
import * as lib from "./lib";
import leftPad from "left-pad";

const lines = [
  greet("hayleigh"),
  `pi is roughly ${lib.PI.toFixed(2)}`,
  `2 + 3 = ${lib.add(2, 3)}`,
  leftPad("bundled by arc", 24, "·"),
];

const text = lines.join("\n");

if (typeof document !== "undefined") {
  document.getElementById("app").textContent = text;
} else {
  console.log(text);
}
