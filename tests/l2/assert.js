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

/** 键名排序的规范化 JSON：只用于「逐字段相等」的深比较，不改变数组顺序。 */
function canonical(value) {
  if (Array.isArray(value)) {
    return '[' + value.map((item) => canonical(item)).join(',') + ']';
  }
  if (value !== null && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return '{' + keys.map((key) => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
  }
  return JSON.stringify(value);
}

/**
 * 深比较：字段集合 + 字段值 + 数组顺序全部相等。
 *
 * 为什么不用 `JSON.stringify(a) === JSON.stringify(b)`：字段插入顺序不同就会假失败，
 * 而 B2 的要求是「逐条逐字段相等」，不是「字符串一模一样」。
 */
function deepEq(name, actual, expected) {
  const a = canonical(actual);
  const b = canonical(expected);
  const same = a === b;
  let detail;
  if (!same) {
    let at = 0;
    while (at < a.length && at < b.length && a.charAt(at) === b.charAt(at)) {
      at += 1;
    }
    detail = '首个差异位置 ' + at + '：actual…' + a.substring(Math.max(0, at - 40), at + 60) +
      ' | expected…' + b.substring(Math.max(0, at - 40), at + 60);
  }
  ok(name, same, detail);
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

module.exports = { ok, eq, throws, deepEq, summary, reset };
