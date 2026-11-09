// btn.js <layout.json> <text> [nth] — 输出匹配节点的中心像素坐标 "x y"，便于 uiInput click
const fs = require('fs');
const [file, needle, nthRaw] = process.argv.slice(2);
if (!file || !needle) { console.error('usage: node btn.js <layout.json> <text> [nth]'); process.exit(1); }
const j = JSON.parse(fs.readFileSync(file, 'utf8'));
const nth = nthRaw ? parseInt(nthRaw, 10) : 0;
const hits = [];
function walk(n) {
  if (!n) return;
  const a = n.attributes || {};
  const t = a.text || '';
  if (t.indexOf(needle) >= 0 && a.bounds) {
    const m = a.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
    if (m) hits.push({ text: t, x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2), type: a.type });
  }
  (n.children || []).forEach(walk);
}
walk(j);
if (hits.length === 0) { console.error('NOT_FOUND: ' + needle); process.exit(2); }
const h = hits[Math.min(nth, hits.length - 1)];
if (process.env.VERBOSE) console.error(hits.map((v, i) => i + ':[' + v.type + '] ' + v.text + ' -> ' + v.x + ',' + v.y).join('\n'));
console.log(h.x + ' ' + h.y);
