// Prints an HTML file from build-docs.py to an A4 PDF with a running header
// and page numbers, using the Chrome that Playwright drives.
//   node tools/evidence/print-pdf.mjs <file.html> [out.pdf]

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = require(path.join(here, "..", "..", "web", "node_modules", "playwright"));

const input = path.resolve(process.argv[2]);
const output = process.argv[3] ? path.resolve(process.argv[3]) : input.replace(/\.html$/, ".pdf");
const header = fs.existsSync(input + ".header.txt") ? fs.readFileSync(input + ".header.txt", "utf8") : "PHILMART";
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");

const browser = await chromium.launch({ channel: "chrome" }).catch(() => chromium.launch());
const page = await browser.newPage();
await page.goto(pathToFileURL(input).href);
await page.pdf({
  path: output,
  format: "A4",
  printBackground: true,
  displayHeaderFooter: true,
  margin: { top: "18mm", bottom: "16mm", left: "16mm", right: "16mm" },
  headerTemplate: `<div style="font-size:7px;color:#667085;width:100%;padding:0 16mm;font-family:Arial">${esc(header)}</div>`,
  footerTemplate: `<div style="font-size:7px;color:#667085;width:100%;padding:0 16mm;font-family:Arial;display:flex;justify-content:space-between;border-top:0.5px solid #e4b23a;padding-top:2mm"><span>${esc(header)}</span><span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span></div>`,
});
await browser.close();
console.log(output);
