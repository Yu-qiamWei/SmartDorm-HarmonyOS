/**
 * 智寓 · T4-02 判据 B8：StorageDiagnostics 环形缓冲（L2）
 *
 * 覆盖：60 条写入后容量 50、`list()` 按 seq 升序、保留最新 50 条（首条 seq === 11）、
 *       `list()` 返回副本（改它不影响内部）、`clear()` 后 seq 继续递增。
 *
 * 运行：`node tests/l2/t402_diagnostics.js`
 */
'use strict';

const { ok, eq, summary } = require('./assert');
const { StorageDiagnostics, DiagnosticLevel } = require('./.gen/out/store/StorageDiagnostics.js');
const { DIAGNOSTIC_CAPACITY } = require('./.gen/out/common/Constants.js');

function main() {
  process.stdout.write('[B8] StorageDiagnostics 环形缓冲\n');

  const diag = StorageDiagnostics.getInstance();
  diag.clear();
  eq('清空后 size = 0', diag.size(), 0);

  for (let i = 1; i <= 60; i++) {
    const level = i % 3 === 0 ? DiagnosticLevel.ERROR
      : (i % 3 === 1 ? DiagnosticLevel.INFO : DiagnosticLevel.WARN);
    diag.record(level, 'CODE_' + i, '第 ' + i + ' 条');
  }
  eq('写 60 条后 size = DIAGNOSTIC_CAPACITY(' + DIAGNOSTIC_CAPACITY + ')',
    diag.size(), DIAGNOSTIC_CAPACITY);
  eq('DIAGNOSTIC_CAPACITY = 50', DIAGNOSTIC_CAPACITY, 50);

  const list = diag.list();
  eq('list() 条数 = 50', list.length, 50);
  eq('保留最新的 50 条：首条 seq = 11', list[0].seq, 11);
  eq('末条 seq = 60', list[list.length - 1].seq, 60);
  let ascending = true;
  for (let i = 1; i < list.length; i++) {
    if (list[i].seq <= list[i - 1].seq) {
      ascending = false;
    }
  }
  ok('list() 按 seq 升序', ascending);
  eq('首条 code = CODE_11（最旧的 10 条已淘汰）', list[0].code, 'CODE_11');
  eq('级别保留正确（第 12 条 % 3 == 0 → ERROR）', list[1].level, DiagnosticLevel.ERROR);
  ok('timestamp 为有效时间戳', list.every((e) => typeof e.timestamp === 'number' && e.timestamp > 0));

  // 副本语义：改返回值不能污染内部
  list[0].code = 'MUTATED';
  list.length = 0;
  eq('外部改动不影响内部（code）', diag.list()[0].code, 'CODE_11');
  eq('外部改动不影响内部（条数）', diag.size(), 50);

  // clear() 后 seq 不回零，继续递增
  diag.clear();
  eq('clear() 后 size = 0', diag.size(), 0);
  diag.record(DiagnosticLevel.INFO, 'AFTER_CLEAR', '清空后第一条');
  eq('clear() 后 seq 继续递增 = 61', diag.list()[0].seq, 61);

  // 容量边界：正好写满 50 条不淘汰
  diag.clear();
  for (let i = 0; i < DIAGNOSTIC_CAPACITY; i++) {
    diag.record(DiagnosticLevel.INFO, 'N_' + i, 'd');
  }
  eq('正好 50 条不淘汰', diag.size(), 50);
  diag.record(DiagnosticLevel.INFO, 'N_50', 'd');
  eq('第 51 条触发淘汰（仍为 50）', diag.size(), 50);
  eq('淘汰的是最旧一条', diag.list()[0].code, 'N_1');

  diag.clear();
  return summary('B8');
}

process.exitCode = main() ? 0 : 1;
