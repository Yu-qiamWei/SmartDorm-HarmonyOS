// Extract runtime meta (KEY-11) and schema version (KEY-01) from a preferences store file.
// Usage: node extract_meta.js <prefs_file>
const fs = require('fs');
const path = process.argv[2];
if (!path) { console.error('usage: node extract_meta.js <prefs_file>'); process.exit(1); }
const t = fs.readFileSync(path, 'utf8');
function val(key) {
  const m = t.match(new RegExp(key + '["\']?>([^<]*)'));
  if (!m) return null;
  return m[1]
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}
const sv = val('smartdorm.meta.schemaVersion');
const rt = val('smartdorm.meta.runtime');
console.log('KEY-01 schemaVersion =', sv);
console.log('KEY-11 runtime raw   =', rt);
if (rt) {
  try {
    const o = JSON.parse(rt);
    console.log('  bootCount     =', o.bootCount);
    console.log('  firstLaunchAt =', o.firstLaunchAt);
    console.log('  lastLaunchAt  =', o.lastLaunchAt);
  } catch (e) {
    console.log('  parse err:', e.message);
  }
}
