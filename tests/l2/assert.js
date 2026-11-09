/**
 * 智寓 · 极简断言器（L2，零依赖）
 *
 * 不做测试框架：阶段五才引入正式执行方案；本文件只提供「打印 PASS/FAIL 并统计」，
 * 保证每条断言都有可粘进证据文件的原文输出。
 */
'use strict';

let passed = 0;
let failed = 0;
const failures = [];

function ok(name, condition, detail) {
  if (condition) {
    passed += 1;
    process.stdout.write('  PASS  ' + name + '\n');
  } else {
    failed += 1;
    failures.push(name + (detail === undefined ? '' : ' → ' + detail));
    process.stdout.write('  FAIL  ' + name + (detail === undefined ? '' : ' → ' + detail) + '\n');
  }
}

function eq(name, actual, expected) {
  const same = actual === expected;
  ok(name, same, same ? undefined : 'actual=' + JSON.stringify(actual) + ' expected=' + JSON.stringify(expected));
}

/** 断言 fn 抛出异常（用于 chunkKey 越界拒绝）。 */
function throws(name, fn) {
  let threw = false;
  try {
    fn();
  } catch (err) {
    threw = true;
  }
  ok(name, threw, threw ? undefined : '未抛异常');
}

function summary(title) {
  process.stdout.write('[' + title + '] ' + passed + ' passed, ' + failed + ' failed\n');
  if (failed > 0) {
    process.stdout.write('  失败项：\n');
    for (const item of failures) {
      process.stdout.write('    - ' + item + '\n');
    }
  }
  return failed === 0;
}

function reset() {
  passed = 0;
  failed = 0;
  failures.length = 0;
}

module.exports = { ok, eq, throws, summary, reset };
