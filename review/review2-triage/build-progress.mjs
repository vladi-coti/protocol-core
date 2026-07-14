#!/usr/bin/env node
/**
 * Scan wayfinder tickets + map.md → progress-data.json (and embed in index.html).
 * Run: node review/wayfinder/build-progress.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TICKETS_DIR = path.join(__dirname, "tickets");
const MAP_PATH = path.join(__dirname, "map.md");
const DATA_PATH = path.join(__dirname, "progress-data.json");
const HTML_PATH = path.join(__dirname, "index.html");

function parseFrontmatter(raw) {
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) return {};
  const fm = {};
  for (const line of match[1].split("\n")) {
    const m = line.match(/^(\w+):\s*(.+)$/);
    if (!m) continue;
    let val = m[2].trim();
    if (val.startsWith("[") && val.endsWith("]")) {
      val = val
        .slice(1, -1)
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    } else if (val === "—" || val === "-") {
      val = null;
    }
    fm[m[1]] = val;
  }
  return fm;
}

function extractQuestion(raw) {
  const m = raw.match(/## Question\s*\n+\s*(.+?)(?:\n\n|\n## )/s);
  return m ? m[1].trim() : "";
}

function extractChecklist(raw) {
  const section = raw.match(/## Resolution checklist\s*\n([\s\S]*?)(?:\n## |$)/);
  if (!section) return { done: 0, total: 0 };
  const items = [...section[1].matchAll(/^- \[([ xX])\]/gm)];
  const done = items.filter((i) => i[1].toLowerCase() === "x").length;
  return { done, total: items.length };
}

function extractVerdict(raw) {
  const answer = raw.match(/## Answer\s*\n([\s\S]*?)$/);
  if (!answer) return { verdict: null, disposition: null, summary: null };
  const body = answer[1];

  let verdict = null;
  const verdictLine = body.match(/\*\*Verdict:\s*`?([^`*\n]+)`?/i);
  if (verdictLine) verdict = verdictLine[1].trim().replace(/\*\*$/, "");

  let disposition = null;
  const dispLine = body.match(/\*\*Fix disposition:\s*`([^`]+)`/i);
  if (dispLine) disposition = dispLine[1].trim();

  let summary = null;
  if (body.includes("*(in progress)*")) summary = "In progress";
  else if (body.includes("*(unresolved)*")) summary = "Unresolved";
  else if (verdict) {
    summary = verdict.split("(")[0].trim();
    if (disposition) summary += ` · ${disposition}`;
  }

  return { verdict, disposition, summary };
}

function parseMapFrontier(mapRaw) {
  const frontier = [];
  const frontierSection = mapRaw.match(/## Frontier \(start here\)\s*\n([\s\S]*?)(?:\n## |$)/);
  if (!frontierSection) return frontier;
  for (const line of frontierSection[1].split("\n")) {
    const m = line.match(/^\d+\.\s+\[(.+?)\]\(tickets\/(.+?)\)/);
    if (m) frontier.push({ title: m[1], file: m[2] });
  }
  return frontier;
}

function parseMapDecisions(mapRaw) {
  const decisions = [];
  const section = mapRaw.match(/## Decisions so far\s*\n([\s\S]*?)(?:\n## |$)/);
  if (!section) return decisions;
  for (const line of section[1].split("\n")) {
    const m = line.match(/^-\s+\[(.+?)\]\(tickets\/(.+?)\)\s+—\s+\*\*(.+?)\*\*(.*)$/);
    if (m) {
      decisions.push({
        title: m[1],
        file: m[2],
        headline: m[3],
        detail: m[4].trim().replace(/^;\s*/, ""),
      });
    }
  }
  return decisions;
}

function groupFromLabels(labels) {
  if (!Array.isArray(labels)) return "other";
  if (labels.includes("group:logic-security")) return "logic";
  if (labels.includes("group:privacy-leak")) return "privacy";
  if (labels.includes("group:design-product")) return "design";
  return "other";
}

function loadTickets() {
  const files = fs.readdirSync(TICKETS_DIR).filter((f) => f.endsWith(".md")).sort();
  return files.map((file) => {
    const raw = fs.readFileSync(path.join(TICKETS_DIR, file), "utf8");
    const fm = parseFrontmatter(raw);
    const checklist = extractChecklist(raw);
    const { verdict, disposition, summary } = extractVerdict(raw);
    return {
      id: fm.id ?? file.replace(/\.md$/, ""),
      file,
      finding: fm.finding ?? null,
      priority: fm.priority ?? "?",
      severity: fm.severity ?? null,
      status: fm.status ?? "open",
      labels: Array.isArray(fm.labels) ? fm.labels : [],
      group: groupFromLabels(fm.labels),
      question: extractQuestion(raw),
      checklist,
      verdict,
      disposition,
      summary,
      blocks: fm.blocks ?? null,
      blocked_by: fm.blocked_by ?? null,
    };
  });
}

function summarize(tickets) {
  const byStatus = { open: 0, "in-progress": 0, closed: 0 };
  const byGroup = {};
  const byPriority = {};
  const byVerdict = {};
  const byDisposition = {};

  for (const t of tickets) {
    byStatus[t.status] = (byStatus[t.status] ?? 0) + 1;
    byGroup[t.group] = byGroup[t.group] ?? { open: 0, "in-progress": 0, closed: 0, total: 0 };
    byGroup[t.group][t.status] = (byGroup[t.group][t.status] ?? 0) + 1;
    byGroup[t.group].total++;

    byPriority[t.priority] = byPriority[t.priority] ?? { open: 0, "in-progress": 0, closed: 0, total: 0 };
    byPriority[t.priority][t.status] = (byPriority[t.priority][t.status] ?? 0) + 1;
    byPriority[t.priority].total++;

    if (t.verdict) {
      const key = t.verdict.split("(")[0].trim().toLowerCase();
      byVerdict[key] = (byVerdict[key] ?? 0) + 1;
    }
    if (t.disposition) {
      byDisposition[t.disposition] = (byDisposition[t.disposition] ?? 0) + 1;
    }
  }

  const checklistTotal = tickets.reduce((a, t) => a + t.checklist.total, 0);
  const checklistDone = tickets.reduce((a, t) => a + t.checklist.done, 0);

  return {
    total: tickets.length,
    byStatus,
    byGroup,
    byPriority,
    byVerdict,
    byDisposition,
    validationProgress: checklistTotal ? Math.round((checklistDone / checklistTotal) * 100) : 0,
    closedPct: Math.round((byStatus.closed / tickets.length) * 100),
  };
}

function main() {
  const mapRaw = fs.readFileSync(MAP_PATH, "utf8");
  const tickets = loadTickets();
  const data = {
    generatedAt: new Date().toISOString(),
    source: "review/wayfinder/tickets/*.md",
    summary: summarize(tickets),
    frontier: parseMapFrontier(mapRaw),
    decisions: parseMapDecisions(mapRaw),
    tickets,
  };

  fs.writeFileSync(DATA_PATH, JSON.stringify(data, null, 2));

  let html = fs.readFileSync(HTML_PATH, "utf8");
  const marker = /const WAYFINDER_DATA = [\s\S]*?\n\n    function loadData\(\)/;
  if (!marker.test(html)) {
    throw new Error(
      "index.html missing WAYFINDER_DATA slot — expected `const WAYFINDER_DATA = ...` before `function loadData()`",
    );
  }
  html = html.replace(
    marker,
    `const WAYFINDER_DATA = ${JSON.stringify(data)};\n\n    function loadData()`,
  );
  // Remove legacy embed format if present from earlier builds.
  html = html.replace(/\n<script id="wayfinder-data" type="application\/json">[\s\S]*?<\/script>/, "");
  fs.writeFileSync(HTML_PATH, html);

  console.log(`Wrote ${DATA_PATH} (${tickets.length} tickets)`);
  console.log(`Embedded data in ${HTML_PATH}`);
  console.log(
    `Status: ${data.summary.byStatus.closed ?? 0} closed, ${data.summary.byStatus["in-progress"] ?? 0} in-progress, ${data.summary.byStatus.open ?? 0} open`,
  );
}

main();
