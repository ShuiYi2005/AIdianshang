import { readFile } from "node:fs/promises";

const stylesheet = await readFile(new URL("../../services/support-console/src/styles.css", import.meta.url), "utf8");
const required = [
  /html,\s*body,\s*#root\s*\{[^}]*height:\s*100%[^}]*overflow:\s*hidden/s,
  /\.app-frame\s*\{[^}]*height:\s*100dvh[^}]*overflow:\s*hidden/s,
  /\.workbench-shell\s*\{[^}]*height:\s*100%[^}]*min-height:\s*0[^}]*overflow:\s*hidden/s,
  /\.message-stream\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s,
  /\.evidence-panel\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s,
  /\.training-shell\s*\{[^}]*height:\s*100%[^}]*min-height:\s*0[^}]*overflow:\s*hidden/s,
  /\.training-editor\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s,
  /safe-area-inset-bottom/,
];

for (const matcher of required) {
  if (!matcher.test(stylesheet)) {
    throw new Error(`missing fixed-shell rule: ${matcher}`);
  }
}

console.log("OK fixed-shell source contract verified");
