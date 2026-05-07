#!/usr/bin/env node
// Run with: node --test scripts/build-release-notes.test.mjs
// Uses only Node built-ins — no external test framework required.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildBody, extractSection, renderDownloadTable } from './build-release-notes.mjs';

const SAMPLE_CHANGELOG = `# Changelog

## [1.1.16] - 2026-05-07

### Highlights / 亮点

- New toggle / 新开关.

### Added 新增

- Persistent setting / 持久化字段.

## [1.1.15] - 2026-04-01

### Fixed

- Earlier fix.

[1.1.16]: https://github.com/ilikebug/VeloxClip/releases/tag/v1.1.16
[1.1.15]: https://github.com/ilikebug/VeloxClip/releases/tag/v1.1.15
`;

test('extractSection picks the right version and stops at the next header', () => {
  const section = extractSection(SAMPLE_CHANGELOG, '1.1.16');
  assert.ok(section, 'section should be found');
  assert.match(section, /Highlights \/ 亮点/);
  assert.match(section, /Persistent setting/);
  assert.doesNotMatch(section, /1\.1\.15/);
  assert.doesNotMatch(section, /Earlier fix/);
});

test('extractSection strips trailing reference-link definitions', () => {
  const section = extractSection(SAMPLE_CHANGELOG, '1.1.16');
  assert.doesNotMatch(section, /\[1\.1\.16\]:\s*https/);
});

test('extractSection returns null for missing version', () => {
  const section = extractSection(SAMPLE_CHANGELOG, '99.0.0');
  assert.equal(section, null);
});

test('renderDownloadTable links the dmg under the right tag', () => {
  const table = renderDownloadTable('v1.1.16');
  assert.match(table, /VeloxClip-v1\.1\.16\.dmg/);
  assert.match(table, /releases\/download\/v1\.1\.16/);
});

test('buildBody assembles header, section, download table and footer', () => {
  const { body, sectionFound } = buildBody('v1.1.16', SAMPLE_CHANGELOG);
  assert.equal(sectionFound, true);
  assert.match(body, /^# Velox Clip v1\.1\.16/);
  assert.match(body, /## Downloads/);
  assert.match(body, /Highlights \/ 亮点/);
  assert.match(body, /Full changelog/);
});

test('buildBody accepts bare version (no v prefix) and normalises', () => {
  const { body } = buildBody('1.1.16', SAMPLE_CHANGELOG);
  assert.match(body, /Velox Clip v1\.1\.16/);
});

test('buildBody returns sectionFound=false and a sparse body when CHANGELOG lacks the version', () => {
  const { body, sectionFound } = buildBody('v9.9.9', SAMPLE_CHANGELOG);
  assert.equal(sectionFound, false);
  assert.match(body, /Velox Clip v9\.9\.9/);
  assert.match(body, /## Downloads/);
  assert.match(body, /Full changelog/);
});
