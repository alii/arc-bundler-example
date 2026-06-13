import { capitalize } from "../lib/strings.mjs";

export function greet(name) {
  return `hello, ${capitalize(name)}!`;
}
