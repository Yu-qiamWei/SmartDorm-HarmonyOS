/**
 * 智寓 · L2 运行入口（阶段四 T4-01）
 *
 * 三步：① `gen.js` 把 `.ets` 复制成 `.ts`；② 用 DevEco 自带 tsc（4.9.5）按 `tsconfig.json` 编译；
 * ③ 依次跑断言文件并汇总退出码。
 *
 * 为什么用 DevEco 自带 tsc 而不是全局 tsc：与工程构建链同一份 TypeScript 实现，
 * 避免「本机 tsc 版本不同导致类型判定差异」这类无法归因的偏差（阶段三 §5.1.1 同口径）。
 *
 * 用法：`node tests/l2/run.js`
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const HERE = __dirname;
const TSC_JS = 'D:/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript/lib/tsc.js';

const TESTS = [
  't401_keys.js',
  't401_queue.js',
  't402_serializer.js',
  't402_migration.js',
  't402_diagnostics.js',
  't403_repository.js'
];

function runNode(args, cwd) {
  const result = spawnSync(process.execPath, args, { cwd: cwd, stdio: 'inherit' });
  if (result.error) {
    throw result.error;
  }
  return result.status === 0;
}

function main() {
  process.stdout.write('== 1/3 生成 .gen/src（.ets → .ts，仅改扩展名）==\n');
  if (!runNode([path.join(HERE, 'gen.js')], HERE)) {
    return 1;
  }

  process.stdout.write('== 2/3 tsc 编译（strict, commonjs, ES2021）==\n');
  if (!fs.existsSync(TSC_JS)) {
    process.stdout.write('未找到 tsc：' + TSC_JS + '\n');
    return 1;
  }
  if (!runNode([TSC_JS, '-p', path.join(HERE, 'tsconfig.json')], HERE)) {
    process.stdout.write('tsc 编译失败，后续断言不执行\n');
    return 1;
  }

  process.stdout.write('== 3/3 执行断言 ==\n');
  let allOk = true;
  for (const test of TESTS) {
    if (!runNode([path.join(HERE, test)], HERE)) {
      allOk = false;
    }
  }
  process.stdout.write(allOk ? '== L2 结果：全部断言通过 ==\n' : '== L2 结果：存在失败断言 ==\n');
  return allOk ? 0 : 1;
}

process.exitCode = main();
