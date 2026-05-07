#!/usr/bin/env node
// Render a rich release body for GitHub Releases by extracting the matching
// version section from CHANGELOG.md and prepending a download table.
//
// Usage:
//   node scripts/build-release-notes.mjs vA.B.C   # writes RELEASE_BODY.md
//
// Exit codes:
//   0  ok
//   1  malformed args / I/O
//   2  CHANGELOG section for this tag is missing — caller should fix CHANGELOG
//      before publishing instead of pushing a near-empty body.

import { readFileSync, writeFileSync } from 'node:fs';
import { argv, exit, stderr, stdout } from 'node:process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = 'ilikebug/VeloxClip';
const ASSET_BASE = `https://github.com/${REPO}/releases/download`;

function buildBody(rawTag, changelogText) {
  const tag = rawTag.startsWith('v') ? rawTag : `v${rawTag}`;
  const version = tag.replace(/^v/, '');

  const section = extractSection(changelogText, version);
  const downloadTable = renderDownloadTable(tag);

  const header = `# Velox Clip ${tag}\n\n${downloadTable}\n`;
  const footer = [
    '',
    '---',
    '',
    `**Full changelog:** [\`CHANGELOG.md\`](https://github.com/${REPO}/blob/${tag}/CHANGELOG.md)`,
    `**All releases:** https://github.com/${REPO}/releases`,
  ].join('\n');

  if (section === null) {
    stderr.write(
      `⚠️  No \`## [${version}]\` section found in CHANGELOG.md. ` +
      `Release body will be sparse — fix CHANGELOG before publishing.\n`
    );
    return { body: `${header}\n${footer}\n`, sectionFound: false };
  }
  return { body: `${header}\n${section.trim()}\n${footer}\n`, sectionFound: true };
}

function extractSection(text, version) {
  // Match `## [X.Y.Z] - DATE` (Keep-a-Changelog) up to the next `## [` header
  // or end of file. Linkified versions like `## [X.Y.Z]` are also supported.
  const headerPattern = new RegExp(
    String.raw`^##\s*\[?\s*${escapeRegex(version)}\s*\]?[^\n]*\n`,
    'm'
  );
  const startMatch = headerPattern.exec(text);
  if (!startMatch) return null;

  const afterHeader = text.slice(startMatch.index + startMatch[0].length);
  const nextHeader = /^##\s/m.exec(afterHeader);
  const body = nextHeader ? afterHeader.slice(0, nextHeader.index) : afterHeader;

  // Strip trailing reference-link definitions like `[1.1.16]: https://...`
  const cleaned = body.replace(/^\[[^\]]+\]:\s*https?:\/\/\S+\s*$/gm, '');
  return cleaned;
}

function renderDownloadTable(tag) {
  const dmg = `${ASSET_BASE}/${tag}/VeloxClip-${tag}.dmg`;
  return [
    '## Downloads',
    '',
    '| Platform | File |',
    '| --- | --- |',
    `| macOS (Apple Silicon + Intel) | [\`VeloxClip-${tag}.dmg\`](${dmg}) |`,
  ].join('\n');
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function main() {
  const tag = argv[2];
  if (!tag) {
    stderr.write('Usage: build-release-notes.mjs <tag>\n');
    exit(1);
  }
  const here = dirname(fileURLToPath(import.meta.url));
  const repoRoot = resolve(here, '..');
  const changelogPath = resolve(repoRoot, 'CHANGELOG.md');
  const outPath = resolve(repoRoot, 'RELEASE_BODY.md');

  let changelog;
  try {
    changelog = readFileSync(changelogPath, 'utf8');
  } catch (err) {
    stderr.write(`Failed to read CHANGELOG.md at ${changelogPath}: ${err.message}\n`);
    exit(1);
  }

  const { body, sectionFound } = buildBody(tag, changelog);
  writeFileSync(outPath, body, 'utf8');
  stdout.write(`Wrote ${outPath} (${body.length} bytes, sectionFound=${sectionFound})\n`);
  exit(sectionFound ? 0 : 2);
}

// Allow direct execution; expose buildBody for tests.
const isDirectRun = fileURLToPath(import.meta.url) === resolve(argv[1] ?? '');
if (isDirectRun) main();

export { buildBody, extractSection, renderDownloadTable };
