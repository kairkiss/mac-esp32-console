#!/usr/bin/env node
const fs = require("fs");

if (process.argv.length !== 5) {
  console.error("usage: merge_v6_flow.js live_flows v6_flow out");
  process.exit(2);
}

const [livePath, v6Path, outPath] = process.argv.slice(2);
const live = JSON.parse(fs.readFileSync(livePath, "utf8"));
const v6 = JSON.parse(fs.readFileSync(v6Path, "utf8"));

const v6Ids = new Set(v6.map((n) => n.id).filter(Boolean));
const filtered = live.filter((n) => !v6Ids.has(n.id) && n.id !== "bkb_tab_v6_lite");

for (const node of filtered) {
  if (node.type === "tab" && /^BKB Desk Node v[0-9]/.test(node.label || "")) {
    node.disabled = true;
  }
  if (node.type === "tab" && (node.label || "") === "BKB Desk Pet v6 Lite") {
    node.disabled = true;
  }
}

const merged = filtered.concat(v6);
fs.writeFileSync(outPath, JSON.stringify(merged, null, 4), "utf8");
console.log(`merged ${v6.length} v6 nodes into ${outPath}`);
