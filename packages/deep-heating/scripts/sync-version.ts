#!/usr/bin/env bun
/**
 * Syncs the version from packages/deep-heating/package.json to packages/deep-heating/config.yaml
 * Run after `changeset version` to keep Home Assistant add-on config in sync.
 */

import { readFileSync, writeFileSync } from 'fs';
import { join } from 'path';

const PACKAGE_DIR = join(import.meta.dir, '..');
const PACKAGE_JSON = join(PACKAGE_DIR, 'package.json');
const CONFIG_YAML = join(PACKAGE_DIR, 'config.yaml');

const packageJson = JSON.parse(readFileSync(PACKAGE_JSON, 'utf-8'));
const version = packageJson.version;

if (!version) {
  console.error('No version found in packages/deep-heating/package.json');
  process.exit(1);
}

const configYaml = readFileSync(CONFIG_YAML, 'utf-8');
const updatedConfig = configYaml.replace(
  /^version:\s*['"]?[^'\n]+['"]?$/m,
  `version: '${version}'`,
);

if (configYaml === updatedConfig) {
  console.log(`config.yaml already at version ${version}`);
} else {
  writeFileSync(CONFIG_YAML, updatedConfig);
  console.log(`Updated config.yaml to version ${version}`);
}
