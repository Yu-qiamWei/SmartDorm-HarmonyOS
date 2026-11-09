// layout.js <layout.json> — 打印组件树中的文本/按钮及其像素坐标，用于断言界面真实内容
const fs = require('fs');
const file = process.argv[2];
if (!file) { console.error('usage: node layout.js <layout.json>'); process.exit(1); }
const j = JSON.parse(fs.readFileSync(file, 'utf8'));

function walk(n, d) {
  if (!n) return;
  const a = n.attributes || {};
  const t = a.text || '';
  const b = a.bounds || '';
  const ty = a.type || '?';
  if (t || ty === 'Button' || ty === 'TextInput') {
    // 解析 [x1,y1][x2,y2] 计算宽高（vp = px / 3.25）
    const m = b.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
    let extra = '';
    if (m) {
      const w = +m[3] - +m[1], h = +m[4] - +m[2];
      extra = ` w=${w}px(${(w / 3.25).toFixed(1)}vp) h=${h}px(${(h / 3.25).toFixed(1)}vp)`;
    }
    console.log(' '.repeat(d) + ty + ' | ' + b + extra + ' | ' + (t || '(no-text)'));
  }
  (n.children || []).forEach((c) => walk(c, d + 1));
}
walk(j, 0);
