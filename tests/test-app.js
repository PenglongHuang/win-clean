const path = require('path');
const app = require(path.join(__dirname, '..', 'report', 'app.js'));

let fails = 0;
function eq(label, expected, actual) {
  if (String(expected) !== String(actual)) {
    console.log(`  FAIL ${label}: expected [${expected}] actual [${actual}]`); fails++;
  } else console.log(`  ok   ${label}`);
}

// fmtBytes
eq('fmt 512 B', '512 B', app.fmtBytes(512));
eq('fmt 1.5 KB', '1.5 KB', app.fmtBytes(1536));
eq('fmt 4.3 GB', '4.3 GB', app.fmtBytes(4.3 * 1024 * 1024 * 1024));

// LEVELS meta completeness
[1, 2, 3, 4, 5].forEach(l => {
  const m = app.LEVELS[l];
  if (!m || !m.color || !m.name || !m.policy) { console.log(`  FAIL LEVELS[${l}] incomplete`); fails++; }
  else console.log(`  ok   LEVELS[${l}] = ${m.name}`);
});

// squarify: area conservation + containment
const items = [{ area: 4.2e9 }, { area: 2.7e9 }, { area: 1.9e9 }, { area: 0.4e9 }, { area: 0.05e9 }];
const laid = app.squarify(items, 0, 0, 1000, 600);
const total = laid.reduce((s, c) => s + c.w * c.h, 0);
if (Math.abs(total - 1000 * 600) > 1000) { console.log(`  FAIL squarify area: ${total} vs ${1000*600}`); fails++; }
else console.log('  ok   squarify area conserved');
const inside = laid.every(c => c.x >= -0.5 && c.y >= -0.5 &&
  c.x + c.w <= 1000.5 && c.y + c.h <= 600.5 && c.w > 0 && c.h > 0);
if (!inside) { console.log('  FAIL squarify containment'); fails++; }
else console.log('  ok   squarify contained in bounds');
// zero-area guard
eq('squarify zero-safe', 0, app.squarify([], 0, 0, 100, 100).length);

console.log(fails === 0 ? '=== test-app: ALL PASSED ===' : `=== test-app: ${fails} FAILED ===`);
process.exit(fails === 0 ? 0 : 1);
