#!/usr/bin/env node
'use strict';

const { execFileSync } = require('child_process');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const args = process.argv.slice(2);

if (args.includes('--version') || args.includes('-v')) {
  const pkg = require(path.join(ROOT, 'package.json'));
  console.log(`claude-prism v${pkg.version}`);
  process.exit(0);
}

if (args.includes('--help') || args.includes('-h')) {
  console.log(`
claude-prism — Multi-AI provider toolkit for Claude Code

Usage:
  npx claud-prism-aireview            Install commands and scripts
  npx claud-prism-aireview --uninstall Remove commands and scripts
  npx claud-prism-aireview --check-only Check prerequisites only
  npx claud-prism-aireview --version   Print version

Docs: https://github.com/tznthou/claude-prism
`);
  process.exit(0);
}

const isUninstall = args.includes('--uninstall');
const script = isUninstall
  ? path.join(ROOT, 'uninstall.sh')
  : path.join(ROOT, 'install.sh');

const passthrough = args.filter(a => a !== '--uninstall');

try {
  execFileSync('bash', [script, ...passthrough], {
    cwd: ROOT,
    stdio: 'inherit',
  });
} catch (err) {
  process.exit(err.status || 1);
}
