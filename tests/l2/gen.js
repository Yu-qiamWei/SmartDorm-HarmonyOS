/**
 * 智寓 · L2 生成脚本（阶段四 T4-01）
 *
 * 作用：把 `entry/src/main/ets/**\/*.ets` 按原目录结构复制成 `tests/l2/.gen/src/**\/*.ts`，
 * **只改扩展名，不改任何 import 说明符**（ArkTS 与 TS 的相对导入写法一致，改说明符反而会掩盖问题）。
 *
 * 为什么需要这一步：hvigor 的 ArkTS 检查器只在真机构建链里跑，Node 侧无法直接 `require` `.ets`；
 * 而 `node --experimental-transform-types` 会擦掉 `interface` 声明却保留具名导入绑定，
 * 导致 ESM 链接期报 "does not provide an export named ..."（阶段三 §5.1.1 注 ① 已实测）。
 * 用 DevEco 自带的 tsc 做类型级导入消解才正确擦除纯类型导入。
 *
 * 用法：`node tests/l2/gen.js`（通常由 `run.js` 调用）。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC_DIR = path.join(ROOT, 'entry', 'src', 'main', 'ets');
const GEN_DIR = path.join(__dirname, '.gen');

/** 递归收集 `.ets` 文件（返回绝对路径）。 */
function walkEts(dir, acc) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkEts(full, acc);
    } else if (entry.isFile() && entry.name.endsWith('.ets')) {
      acc.push(full);
    }
  }
  return acc;
}

function main() {
  if (!fs.existsSync(SRC_DIR)) {
    throw new Error('源目录不存在：' + SRC_DIR);
  }
  fs.rmSync(GEN_DIR, { recursive: true, force: true });
  const files = walkEts(SRC_DIR, []);
  for (const file of files) {
    const rel = path.relative(SRC_DIR, file).replace(/\.ets$/, '.ts');
    const dest = path.join(GEN_DIR, 'src', rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(file, dest);
  }
  process.stdout.write('[gen] 复制 ' + files.length + ' 个 .ets → .gen/src/**/*.ts\n');
}

main();
