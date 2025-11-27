#!/usr/bin/env bun
/**
 * Creates and pushes a git tag for the deep-heating release.
 * Run by changesets/action after version PR is merged.
 * The tag triggers the Docker build workflow.
 */

import { readFileSync } from 'fs';
import { join } from 'path';
import { $ } from 'bun';

const PACKAGE_DIR = join(import.meta.dir, '..');
const PACKAGE_JSON = join(PACKAGE_DIR, 'package.json');

const packageJson = JSON.parse(readFileSync(PACKAGE_JSON, 'utf-8'));
const version = packageJson.version;

if (!version) {
  console.error('No version found in packages/deep-heating/package.json');
  process.exit(1);
}

const tag = `v${version}`;

// Check if tag already exists
const existingTags = await $`git tag -l ${tag}`.text();
if (existingTags.trim() === tag) {
  console.log(`Tag ${tag} already exists, skipping`);
  process.exit(0);
}

console.log(`Creating tag ${tag}...`);
await $`git tag -a ${tag} -m "Release ${tag}"`;

console.log(`Pushing tag ${tag}...`);
await $`git push origin ${tag}`;

console.log(`Released ${tag}`);
