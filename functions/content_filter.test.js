'use strict';
// Kiểm thử bộ lọc từ ngữ phía server: `node functions/content_filter.test.js` (không cần thư viện).
// Dùng chung ca kiểm thử với test/content_filter_test.dart và kiểm tra danh sách từ giống bản Dart.
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const f = require('./content_filter');

const root = path.join(__dirname, '..');
const cases = JSON.parse(fs.readFileSync(path.join(root, 'test/content_filter_cases.json'), 'utf8'));

for (const t of cases.clean) {
  assert.strictEqual(f.isFlagged(t), false, `không được lọc: "${t}" → "${f.mask(t)}"`);
  assert.strictEqual(f.mask(t), t);
}
for (const [input, expected] of Object.entries(cases.masked)) {
  assert.strictEqual(f.isFlagged(input), true, `phải lọc: "${input}"`);
  assert.strictEqual(f.mask(input), expected, `che "${input}"`);
}
assert.strictEqual(f.mask(undefined), '');

// Danh sách từ phải giống hệt lib/services/content_filter.dart.
const dart = fs.readFileSync(path.join(root, 'lib/services/content_filter.dart'), 'utf8');
function section(src, name) {
  const m = src.match(new RegExp(`// BEGIN ${name}([\\s\\S]*?)// END ${name}`));
  assert.ok(m, `thiếu khối ${name}`);
  return [...m[1].replace(/\/\/.*$/gm, '').matchAll(/'([^']*)'/g)].map((x) => x[1]);
}
assert.deepStrictEqual(section(dart, 'WORDS'), f.WORDS, 'WORDS khác bản Dart');
assert.deepStrictEqual(section(dart, 'STRICT'), f.STRICT, 'STRICT khác bản Dart');
assert.ok(f.WORDS.length + f.STRICT.length >= 100);

console.log(`content_filter: OK (${cases.clean.length} sạch, ${Object.keys(cases.masked).length} bị che, ` +
  `${f.WORDS.length + f.STRICT.length} từ)`);
