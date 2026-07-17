import { expect, it } from "vitest";
import stylesheet from "./styles.css?raw";

it("locks the document root and defines an isolated audit scroll region", () => {
  expect(stylesheet).toMatch(/html,\s*body,\s*#root\s*\{[^}]*height:\s*100%[^}]*overflow:\s*hidden/s);
  expect(stylesheet).toMatch(/\.app-frame\s*\{[^}]*height:\s*100dvh[^}]*overflow:\s*hidden/s);
  expect(stylesheet).toMatch(/\.audit-scroll\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s);
});

it("defines isolated workbench scroll regions and a grid-pinned reply composer", () => {
  expect(stylesheet).toMatch(/\.workbench-shell\s*\{[^}]*height:\s*100%[^}]*min-height:\s*0[^}]*overflow:\s*hidden/s);
  expect(stylesheet).toMatch(/\.message-stream\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s);
  expect(stylesheet).toMatch(/\.evidence-panel\s*\{[^}]*min-height:\s*0[^}]*overflow-y:\s*auto/s);
  expect(stylesheet).toMatch(/\.reply-composer\s*\{[^}]*grid-row:\s*-1[^}]*safe-area-inset-bottom/s);
});
