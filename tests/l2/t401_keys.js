/**
 * 智寓 · T4-01 判据 A2：分块键拼接与解析（L2）
 *
 * 覆盖：`chunkKey` 4 位补零与越界拒绝、`chunkIndexOf` 四条边界
 * （`.hdr` / 位数不足 / 非本基键 / 非数字后缀）、`baseOfPartition`、`isChunked`、
 * 键名长度预算（自定 ≤ 60 字符，`MAX_KEY_LENGTH` = 80）。
 *
 * 运行：`node tests/l2/t401_keys.js`（需先由 run.js 生成 .gen 并编译）
 */
'use strict';

const { ok, eq, throws, summary } = require('./assert');
const { StorageKeys, StoragePartition } = require('./.gen/out/store/StorageKeys.js');
const { CHUNK_INDEX_MAX } = require('./.gen/out/common/Constants.js');

const OP_BASE = StorageKeys.KEY_07_OPERATION_LOGS; // 'smartdorm.logs.operation'
const RULE_BASE = StorageKeys.KEY_08_RULE_EXEC_LOGS;

function main() {
  process.stdout.write('[A2] StorageKeys 分块键工具\n');

  // ——— chunkKey：4 位零填充 ———
  eq('chunkKey(base, 3) === base + ".c0003"',
    StorageKeys.chunkKey(OP_BASE, 3), 'smartdorm.logs.operation.c0003');
  eq('chunkKey(base, 0) === base + ".c0000"',
    StorageKeys.chunkKey(OP_BASE, 0), 'smartdorm.logs.operation.c0000');
  eq('chunkKey(base, 199) === base + ".c0199"',
    StorageKeys.chunkKey(OP_BASE, 199), 'smartdorm.logs.operation.c0199');
  eq('chunkKey(base, CHUNK_INDEX_MAX) === base + ".c9999"',
    StorageKeys.chunkKey(OP_BASE, CHUNK_INDEX_MAX), 'smartdorm.logs.operation.c9999');

  // ——— chunkKey：越界与非整数必须拒绝（不得退化成 5 位序号） ———
  throws('chunkKey(base, CHUNK_INDEX_MAX + 1) 抛错',
    () => StorageKeys.chunkKey(OP_BASE, CHUNK_INDEX_MAX + 1));
  throws('chunkKey(base, -1) 抛错', () => StorageKeys.chunkKey(OP_BASE, -1));
  throws('chunkKey(base, 1.5) 抛错', () => StorageKeys.chunkKey(OP_BASE, 1.5));

  // ——— headerKey ———
  eq('headerKey(base) === base + ".hdr"',
    StorageKeys.headerKey(OP_BASE), 'smartdorm.logs.operation.hdr');

  // ——— chunkIndexOf：正向 ———
  eq('chunkIndexOf(base.c0003, base) === 3',
    StorageKeys.chunkIndexOf(StorageKeys.chunkKey(OP_BASE, 3), OP_BASE), 3);
  eq('chunkIndexOf(base.c9999, base) === 9999',
    StorageKeys.chunkIndexOf(StorageKeys.chunkKey(OP_BASE, CHUNK_INDEX_MAX), OP_BASE), 9999);
  eq('chunkIndexOf 与 chunkKey 互为逆运算（0..12 全等）',
    Array.from({ length: 13 }, (_v, i) => StorageKeys.chunkIndexOf(StorageKeys.chunkKey(OP_BASE, i), OP_BASE))
      .every((v, i) => v === i), true);

  // ——— chunkIndexOf：四条边界 ———
  eq('边界 ① base.hdr → -1',
    StorageKeys.chunkIndexOf(StorageKeys.headerKey(OP_BASE), OP_BASE), -1);
  eq('边界 ② base.c12（位数不足）→ -1',
    StorageKeys.chunkIndexOf(OP_BASE + '.c12', OP_BASE), -1);
  eq('边界 ② base.c00001（5 位）→ -1',
    StorageKeys.chunkIndexOf(OP_BASE + '.c00001', OP_BASE), -1);
  eq('边界 ③ otherBase.c0001 → -1',
    StorageKeys.chunkIndexOf(StorageKeys.chunkKey(RULE_BASE, 1), OP_BASE), -1);
  eq('边界 ③ base 前缀被更长基键吞掉（operation vs operation2）→ -1',
    StorageKeys.chunkIndexOf('smartdorm.logs.operation2.c0001', OP_BASE), -1);
  eq('边界 ④ base.c00a1（非数字后缀）→ -1',
    StorageKeys.chunkIndexOf(OP_BASE + '.c00a1', OP_BASE), -1);
  eq('边界 ④ base.c-001（含负号）→ -1',
    StorageKeys.chunkIndexOf(OP_BASE + '.c-001', OP_BASE), -1);
  eq('基键本身 → -1', StorageKeys.chunkIndexOf(OP_BASE, OP_BASE), -1);

  // ——— 分区 → 基键 ———
  eq('baseOfPartition(DEVICES)', StorageKeys.baseOfPartition(StoragePartition.DEVICES), 'smartdorm.devices');
  eq('baseOfPartition(RULES)', StorageKeys.baseOfPartition(StoragePartition.RULES), 'smartdorm.rules');
  eq('baseOfPartition(SCENES)', StorageKeys.baseOfPartition(StoragePartition.SCENES), 'smartdorm.scenes');
  eq('baseOfPartition(SETTINGS)', StorageKeys.baseOfPartition(StoragePartition.SETTINGS), 'smartdorm.settings');
  eq('baseOfPartition(ENVIRONMENT)', StorageKeys.baseOfPartition(StoragePartition.ENVIRONMENT), 'smartdorm.environment');
  eq('baseOfPartition(OPERATION_LOGS)', StorageKeys.baseOfPartition(StoragePartition.OPERATION_LOGS), 'smartdorm.logs.operation');
  eq('baseOfPartition(RULE_EXEC_LOGS)', StorageKeys.baseOfPartition(StoragePartition.RULE_EXEC_LOGS), 'smartdorm.logs.ruleExec');
  eq('baseOfPartition(ENVIRONMENT_LOGS)', StorageKeys.baseOfPartition(StoragePartition.ENVIRONMENT_LOGS), 'smartdorm.logs.environment');
  eq('baseOfPartition(RETURN_SNAPSHOT)', StorageKeys.baseOfPartition(StoragePartition.RETURN_SNAPSHOT), 'smartdorm.state.returnSnapshot');
  eq('baseOfPartition(META) 防御性默认 KEY_01',
    StorageKeys.baseOfPartition(StoragePartition.META), StorageKeys.KEY_01_SCHEMA_VERSION);

  // ——— isChunked ———
  eq('isChunked(META) === false', StorageKeys.isChunked(StoragePartition.META), false);
  eq('isChunked(DEVICES) === true', StorageKeys.isChunked(StoragePartition.DEVICES), true);
  eq('isChunked(RETURN_SNAPSHOT) === true', StorageKeys.isChunked(StoragePartition.RETURN_SNAPSHOT), true);

  // ——— 键组 ———
  eq('SCALAR_KEYS 长度 2', StorageKeys.SCALAR_KEYS.length, 2);
  eq('SCALAR_KEYS 含 KEY-01 与 KEY-11',
    StorageKeys.SCALAR_KEYS.join('|'),
    StorageKeys.KEY_01_SCHEMA_VERSION + '|' + StorageKeys.KEY_11_RUNTIME);
  eq('CHUNKED_BASES 长度 9', StorageKeys.CHUNKED_BASES.length, 9);
  eq('ALL 长度 11（KEY-01..KEY-11）', StorageKeys.ALL.length, 11);
  eq('KEY_11_RUNTIME === smartdorm.meta.runtime',
    StorageKeys.KEY_11_RUNTIME, 'smartdorm.meta.runtime');
  ok('ALL 无重复键', new Set(StorageKeys.ALL).size === StorageKeys.ALL.length);
  ok('基键本身不在 CHUNKED_BASES 与 SCALAR_KEYS 之外出现遗漏',
    StorageKeys.CHUNKED_BASES.every((b) => StorageKeys.ALL.indexOf(b) >= 0));

  // ——— 键名长度预算：MAX_KEY_LENGTH = 80，自定 ≤ 60 ———
  let maxLen = 0;
  let maxKey = '';
  for (const base of StorageKeys.CHUNKED_BASES) {
    const candidates = [
      StorageKeys.headerKey(base),
      StorageKeys.chunkKey(base, CHUNK_INDEX_MAX)
    ];
    for (const key of candidates) {
      if (key.length > maxLen) {
        maxLen = key.length;
        maxKey = key;
      }
    }
  }
  for (const scalar of StorageKeys.SCALAR_KEYS) {
    if (scalar.length > maxLen) {
      maxLen = scalar.length;
      maxKey = scalar;
    }
  }
  ok('最长派生键 ≤ 40 字符（自定预算 60，SDK 上限 80）', maxLen <= 40, 'max=' + maxLen + ' key=' + maxKey);

  return summary('A2');
}

process.exitCode = main() ? 0 : 1;
