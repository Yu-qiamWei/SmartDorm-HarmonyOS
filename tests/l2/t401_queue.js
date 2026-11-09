/**
 * 智寓 · T4-01 判据 A3 / A4 / A7 / A8：WriteQueue 合并、串行、失败保 dirty、写入顺序、块收缩（L2）
 *
 * A3：连续 `mark([DEVICES])` 5 次 → 只产生 1 个写周期；`flushNow()` 重入返回同一 Promise。
 * A4：写任务抛异常 → 该分区仍在 `pendingPartitions()`，`stats().failures` +1，其他分区不受影响。
 * A7：注入 fake `PartitionWriter` 记录调用序列 → 单分区 `writeChunks` → `writeHeader` → `trimChunks`，
 *     整批只在末尾 1 次 `flushOnce()`。
 * A8：同分区连续写两次（第二次条目更少）→ 键数 = 块头 `n` + 1，且不存在索引 ≥ `n` 的残块。
 *
 * 说明：ArkTS 的 `private constructor` 只是编译期约束，运行时可用 `new WriteQueue()` 取独立实例，
 * 这样每条用例互不污染单例状态。被测语义与生产路径完全一致（`getInstance()` 返回的也是本类实例）。
 *
 * 运行：`node tests/l2/t401_queue.js`
 */
'use strict';

const { ok, eq, summary } = require('./assert');
const { WriteQueue } = require('./.gen/out/store/WriteQueue.js');
const { StorageKeys, StoragePartition } = require('./.gen/out/store/StorageKeys.js');

const DEVICES = StoragePartition.DEVICES;
const RULES = StoragePartition.RULES;
const SETTINGS = StoragePartition.SETTINGS;
const ENV_LOGS = StoragePartition.ENVIRONMENT_LOGS;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** 最小 AppState 替身：`WriteQueue` 只把它原样透传给 encoder，不读任何字段。 */
const FAKE_STATE = { devices: [], rules: [], scenes: [], logs: {} };

/**
 * Fake 编码器：按 `plan[partition]` 返回块数组（默认 1 块）。
 * 真实实现在 T4-02（`Serializer.encodePartition(...).chunks`）。
 */
function makeEncoder(plan) {
  return {
    encodeChunks(partition, _state) {
      if (plan !== undefined && plan[partition] !== undefined) {
        return plan[partition];
      }
      return ['{}'];
    }
  };
}

/**
 * Fake 写面：既记录调用序列（A7），也维护一份「键集合」（A8）。
 * `trimChunks` 的语义按 §4.2 契约实现：删除所有索引 ≥ keepCount 的残块，且**幂等**。
 */
function makeWriter() {
  const writer = {
    ops: [],
    keys: new Set(),          // 全量键名
    headers: new Map(),       // partition → ChunkHeader
    maxSeen: new Map(),       // partition → 见过的最大块序号
    failOn: new Set(),        // 写这些分区时抛错
    failFlush: false,
    flushCount: 0,

    async writeChunks(partition, chunks) {
      writer.ops.push('chunks:' + partition + ':' + chunks.length);
      if (writer.failOn.has(partition)) {
        throw new Error('fake writeChunks 失败：' + partition);
      }
      const base = StorageKeys.baseOfPartition(partition);
      for (let i = 0; i < chunks.length; i++) {
        writer.keys.add(StorageKeys.chunkKey(base, i));
        const seen = writer.maxSeen.get(partition);
        if (seen === undefined || i > seen) {
          writer.maxSeen.set(partition, i);
        }
      }
    },
    async writeHeader(partition, header) {
      writer.ops.push('header:' + partition + ':' + header.n);
      writer.headers.set(partition, header);
      writer.keys.add(StorageKeys.headerKey(StorageKeys.baseOfPartition(partition)));
    },
    async trimChunks(partition, keepCount) {
      writer.ops.push('trim:' + partition + ':' + keepCount);
      const base = StorageKeys.baseOfPartition(partition);
      const seen = writer.maxSeen.get(partition);
      if (seen === undefined) {
        return;
      }
      for (let i = keepCount; i <= seen; i++) {
        writer.keys.delete(StorageKeys.chunkKey(base, i));
      }
      writer.maxSeen.set(partition, keepCount - 1);
    },
    async flushOnce() {
      writer.ops.push('flush');
      writer.flushCount += 1;
      if (writer.failFlush) {
        throw new Error('fake flushOnce 失败');
      }
    },

    /** 该分区在键集合中的键数（块头 + 数据块）。 */
    keysOf(partition) {
      const base = StorageKeys.baseOfPartition(partition);
      let count = 0;
      for (const key of writer.keys) {
        if (key === StorageKeys.headerKey(base) || StorageKeys.chunkIndexOf(key, base) >= 0) {
          count += 1;
        }
      }
      return count;
    },
    /** 该分区是否存在索引 ≥ n 的残块（A8 的「不多不少」判据）。 */
    hasOrphan(partition) {
      const header = writer.headers.get(partition);
      if (header === undefined) {
        return false;
      }
      const base = StorageKeys.baseOfPartition(partition);
      for (const key of writer.keys) {
        const index = StorageKeys.chunkIndexOf(key, base);
        if (index >= header.n) {
          return true;
        }
      }
      return false;
    }
  };
  return writer;
}

function makeQueue(writer, encoder) {
  const queue = new WriteQueue();
  queue.configure(() => FAKE_STATE, writer);
  queue.setEncoder(encoder);
  return queue;
}

// ——————————————————————————————————————————————————————————————
// A3：合并与重入去重
// ——————————————————————————————————————————————————————————————
async function caseA3() {
  process.stdout.write('[A3] 合并与重入去重\n');
  const writer = makeWriter();
  const queue = makeQueue(writer, makeEncoder(undefined));

  for (let i = 0; i < 5; i++) {
    queue.mark([DEVICES]);
  }
  eq('5 次 mark 后 pendingPartitions 只有 1 个分区', queue.pendingPartitions().length, 1);
  await queue.flushNow();
  eq('5 次 mark 只产生 1 个写周期', queue.stats().writeCycles, 1);
  eq('flushOnce 只调用 1 次', writer.flushCount, 1);
  eq('写完后 pendingPartitions 为空', queue.pendingPartitions().length, 0);

  await sleep(320); // 用户车道窗口 200 ms：定时器应已被 flushNow 取消
  eq('debounce 定时器未产生额外写周期', queue.stats().writeCycles, 1);

  queue.mark([DEVICES]);
  const first = queue.flushNow();
  const second = queue.flushNow();
  eq('flushNow 重入返回同一 Promise 实例', first === second, true);
  await first;
  eq('重入未重复写（累计 2 个周期）', queue.stats().writeCycles, 2);
}

// ——————————————————————————————————————————————————————————————
// A4：失败保 dirty、不阻断其他分区
// ——————————————————————————————————————————————————————————————
async function caseA4() {
  process.stdout.write('[A4] 写失败保持 dirty\n');
  const writer = makeWriter();
  writer.failOn.add(DEVICES);
  const queue = makeQueue(writer, makeEncoder(undefined));

  queue.mark([DEVICES, RULES]);
  await queue.flushNow();

  const pending = queue.pendingPartitions();
  ok('失败分区 DEVICES 仍在 pendingPartitions 中', pending.indexOf(DEVICES) >= 0, 'pending=' + pending.join(','));
  ok('成功分区 RULES 已移出 pendingPartitions', pending.indexOf(RULES) < 0, 'pending=' + pending.join(','));
  eq('stats().failures === 1', queue.stats().failures, 1);
  ok('stats().lastError 含分区名', queue.stats().lastError.indexOf('DEVICES') >= 0, queue.stats().lastError);
  eq('块头只写给了 RULES',
    writer.headers.has(RULES) && !writer.headers.has(DEVICES), true);
  eq('failStreak() === 1', queue.failStreak(), 1);

  // flushOnce 失败：同批所有分区都必须保持 dirty（§1.2.1 第 1 条）
  const writer2 = makeWriter();
  writer2.failFlush = true;
  const queue2 = makeQueue(writer2, makeEncoder(undefined));
  queue2.mark([DEVICES, RULES]);
  await queue2.flushNow();
  eq('flushOnce 失败 → 两个分区都保持 dirty', queue2.pendingPartitions().length, 2);
  eq('flushOnce 失败 → failures 记为 1', queue2.stats().failures, 1);

  // 恢复后能重试成功，streak 清零
  writer2.failFlush = false;
  await queue2.flushNow();
  eq('重试成功后 pendingPartitions 清空', queue2.pendingPartitions().length, 0);
  eq('重试成功后 failStreak 清零', queue2.failStreak(), 0);
}

// ——————————————————————————————————————————————————————————————
// A7：写入顺序契约
// ——————————————————————————————————————————————————————————————
async function caseA7() {
  process.stdout.write('[A7] 写入顺序与单批 flushOnce\n');

  const writer1 = makeWriter();
  const queue1 = makeQueue(writer1, makeEncoder({ [DEVICES]: ['{}', '{}'] }));
  queue1.mark([DEVICES]);
  await queue1.flushNow();
  eq('单分区顺序：chunks → header → trim → flush',
    writer1.ops.join(' | '),
    'chunks:' + DEVICES + ':2 | header:' + DEVICES + ':2 | trim:' + DEVICES + ':2 | flush');

  const writer2 = makeWriter();
  const queue2 = makeQueue(writer2, makeEncoder(undefined));
  queue2.mark([DEVICES, RULES, SETTINGS]);
  await queue2.flushNow();
  const ops = writer2.ops;
  eq('多分区批次只在末尾出现 1 次 flushOnce',
    ops.filter((op) => op === 'flush').length, 1);
  eq('flushOnce 是最后一步', ops[ops.length - 1], 'flush');
  eq('每个分区都是 chunks → header → trim',
    ops.slice(0, 9).join(' | '),
    'chunks:' + DEVICES + ':1 | header:' + DEVICES + ':1 | trim:' + DEVICES + ':1 | ' +
    'chunks:' + RULES + ':1 | header:' + RULES + ':1 | trim:' + RULES + ':1 | ' +
    'chunks:' + SETTINGS + ':1 | header:' + SETTINGS + ':1 | trim:' + SETTINGS + ':1');

  // 块头内容：n 等于块数，v 为块格式版本 1，p 为分区
  const header = writer2.headers.get(DEVICES);
  eq('块头 n === 块数', header.n, 1);
  eq('块头 v === 1（块格式版本）', header.v, 1);
  eq('块头 p === 分区', header.p, DEVICES);
  ok('块头 t 为有效时间戳', typeof header.t === 'number' && header.t > 0, String(header.t));
}

// ——————————————————————————————————————————————————————————————
// A8：块收缩后「键数 = 块头 n + 1」
// ——————————————————————————————————————————————————————————————
async function caseA8() {
  process.stdout.write('[A8] 块收缩后键数 = 块头 n + 1\n');
  const writer = makeWriter();
  const plan = { [DEVICES]: ['{}', '{}', '{}'] };
  const queue = makeQueue(writer, makeEncoder(plan));

  queue.mark([DEVICES]);
  await queue.flushNow();
  eq('第一次写 3 块 → 键数 4（= n + 1）', writer.keysOf(DEVICES), 4);
  eq('第一次写后无残块', writer.hasOrphan(DEVICES), false);

  // 第二次条目更少：1 块
  plan[DEVICES] = ['{}'];
  queue.mark([DEVICES]);
  await queue.flushNow();
  const header = writer.headers.get(DEVICES);
  eq('第二次写块头 n === 1', header.n, 1);
  eq('第二次写后键数 2（= n + 1）', writer.keysOf(DEVICES), 2);
  eq('第二次写后不存在索引 ≥ n 的残块', writer.hasOrphan(DEVICES), false);

  // 幂等性：重复 trim 同一 keepCount 不应再改变键集合
  const before = writer.keysOf(DEVICES);
  await writer.trimChunks(DEVICES, 1);
  eq('trimChunks 幂等', writer.keysOf(DEVICES), before);
}

// ——————————————————————————————————————————————————————————————
// 附加：两车道触发（用户 200 ms / 日志累计 20 次）
// ——————————————————————————————————————————————————————————————
async function caseLanes() {
  process.stdout.write('[附加] 两车道触发\n');

  const writer1 = makeWriter();
  const queue1 = makeQueue(writer1, makeEncoder(undefined));
  queue1.mark([SETTINGS]);
  await sleep(320);
  await queue1.drain();
  eq('用户车道 200 ms 后自动落盘 1 次', queue1.stats().writeCycles, 1);

  const writer2 = makeWriter();
  const queue2 = makeQueue(writer2, makeEncoder(undefined));
  for (let i = 0; i < 20; i++) {
    queue2.mark([ENV_LOGS]);
  }
  await queue2.drain();
  eq('日志车道累计 20 次写先到者触发 1 次', queue2.stats().writeCycles, 1);

  // 未配置 encoder / writer 时必须保留 dirty 且记失败，不得静默丢
  const naked = new WriteQueue();
  naked.mark([DEVICES]);
  await naked.flushNow();
  eq('未装配时保留 dirty', naked.pendingPartitions().length, 1);
  eq('未装配时 failures 记为 1', naked.stats().failures, 1);
}

async function main() {
  await caseA3();
  await caseA4();
  await caseA7();
  await caseA8();
  await caseLanes();
  return summary('A3/A4/A7/A8');
}

main().then((okAll) => {
  process.exitCode = okAll ? 0 : 1;
}).catch((err) => {
  process.stdout.write('[FATAL] ' + (err && err.stack ? err.stack : String(err)) + '\n');
  process.exitCode = 1;
});
