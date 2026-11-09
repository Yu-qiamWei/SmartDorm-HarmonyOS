/**
 * 智寓 · L2 断言：T4-03 仓储接线（`AppDataRepository` 真实 load / flush / saveNowSync）
 *
 * 覆盖任务书 C10 / C10b / C10c / L1，另加三组「落盘证据」断言（键名形状 / 落盘可达 / 重启可读）。
 *
 * ★ 这一组是**唯一**能真正跑到 `AppDataRepository` 的 L2：它依赖 `@kit.ArkData` 与
 *   `@kit.AbilityKit`，靠 `tests/l2/stubs/` + `kit_alias.js` 在 Node 里造出内存/磁盘两层的
 *   假 `preferences`。假实现的语义与真机一致：`put` 只改内存，`flush` 才写磁盘——
 *   所以「写失败」与「写成功」在断言里是可区分的，C10 才有意义。
 *
 * 失败注入点：假 `preferences.flush()`。`WriteQueue` 每批只调一次 `flushOnce()`，
 * 因此一次 `failFlush(1)` 恰好让**整批**失败（不是逐个分区各失败一次），
 * 这正是 §1.2-C「整批一次 flush」要验证的形状。
 *
 * 用法：`node tests/l2/t403_repository.js`（通常由 `run.js` 调用）。
 */
'use strict';

require('./kit_alias');

const { ok, eq, deepEq, summary, reset } = require('./assert');

const { FakePrefsControl } = require('./.gen/out/__stub/kit_arkdata');
const { AppDataRepository } = require('./.gen/out/store/AppDataRepository');
const { PreferencesStore } = require('./.gen/out/store/PreferencesStore');
const { StorageDiagnostics } = require('./.gen/out/store/StorageDiagnostics');
const { StorageKeys } = require('./.gen/out/store/StorageKeys');

const STORE = 'smartdorm_store';

/** 深拷贝（只比字段与值，不比对象引用；`getState()` 返回的是活对象）。 */
function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

/** 分区名排序后比较，避免依赖 `Set` 插入顺序。 */
function sortedNames(names) {
  return names.slice().sort();
}

/** 从磁盘键名里算出「每个分块基键有几个块」，用于核对 `.hdr` 的 `n` 与真实块数一致。 */
function chunkCounts(keys) {
  const counts = {};
  for (const key of keys) {
    const hit = /^(.*)\.c(\d{4})$/.exec(key);
    if (hit !== null) {
      counts[hit[1]] = (counts[hit[1]] || 0) + 1;
    }
  }
  return counts;
}

async function main() {
  // ══════════════════════════════════════════════════════════════════════════
  // 前置：冷启动（清空假存储 → init 句柄 → load）
  // ══════════════════════════════════════════════════════════════════════════
  FakePrefsControl.reset();
  StorageDiagnostics.getInstance().clear();

  const repo = AppDataRepository.getInstance();
  const prefs = PreferencesStore.getInstance();

  prefs.init({});
  ok('C0-a PreferencesStore.init 后 isReady() 为真（桩句柄可用）', prefs.isReady() === true);

  const firstState = repo.load();
  ok('C0-b 首启 load() 返回默认态：6 个设备', firstState.devices.length === 6,
    'actual=' + firstState.devices.length);
  ok('C0-c 首启 load() 返回默认态：4 个预置场景', firstState.scenes.length === 4,
    'actual=' + firstState.scenes.length);
  eq('C0-d 首启 bootCount = 1', repo.getRuntimeMeta().bootCount, 1);
  eq('C0-e 首启 rules 为空（护栏 A-6：不预置演示规则）', firstState.rules.length, 0);
  eq('C0-f 首启 ruleExecutions 为空（护栏 A-6：不预置执行日志）',
    firstState.logs.ruleExecutions.length, 0);
  eq('C0-g schemaVersion 已写为当前版本', firstState.schemaVersion, 1);
  ok('C0-h 首启后 10 个分区全部待落盘（load 只 mark 不 await）',
    repo.dirtyPartitions().length === 10, 'actual=' + JSON.stringify(repo.dirtyPartitions()));
  ok('C0-i 首启时磁盘为空（load 未阻塞落盘，此刻还没写）',
    FakePrefsControl.diskOf(STORE).size === 0,
    'actual=' + FakePrefsControl.diskOf(STORE).size);
  const diagnostics = repo.getDiagnostics();
  ok('C0-j 诊断含 LOAD_DONE 且首启=true',
    diagnostics.some((entry) => entry.code === 'LOAD_DONE' &&
      entry.detail.indexOf('首启=true') >= 0),
    'codes=' + JSON.stringify(diagnostics.map((entry) => entry.code)));
  ok('C0-k 诊断含 LOAD_ENUM（allKeys 走 getAllSync 一次取键，不是逐键探测）',
    diagnostics.some((entry) => entry.code === 'LOAD_ENUM'),
    'codes=' + JSON.stringify(diagnostics.map((entry) => entry.code)));

  // ══════════════════════════════════════════════════════════════════════════
  // C10：落盘失败 → STORAGE_ERROR，内存态不动，分区仍 dirty，streak=1
  // ══════════════════════════════════════════════════════════════════════════
  StorageDiagnostics.getInstance().clear();
  const stateBefore = clone(repo.getState());
  const failuresBefore = repo.queueStats().failures;

  FakePrefsControl.failFlush(1);
  const failedResult = await repo.flush();

  eq('C10-a 落盘失败返回 STORAGE_ERROR', failedResult.code, 'STORAGE_ERROR');
  eq('C10-b 落盘失败 success = false', failedResult.success, false);
  ok('C10-c message 非空（沿用 messageOf(STORAGE_ERROR)，不新造文案）',
    typeof failedResult.message === 'string' && failedResult.message.length > 0,
    'message=' + failedResult.message);
  deepEq('C10-d 失败后 getState() 与失败前逐字段完全一致', repo.getState(), stateBefore);
  ok('C10-e 失败后 10 个分区仍全部 dirty（dirty 只在 flushOnce 成功后删）',
    repo.dirtyPartitions().length === 10,
    'actual=' + JSON.stringify(repo.dirtyPartitions()));
  ok('C10-f 失败后 dirty 集合仍含 DEVICES / RULES / RULE_EXEC_LOGS',
    ['DEVICES', 'RULES', 'RULE_EXEC_LOGS'].every((name) => repo.dirtyPartitions().indexOf(name) >= 0),
    'actual=' + JSON.stringify(sortedNames(repo.dirtyPartitions())));
  eq('C10-g 失败后 failStreak = 1', repo.storageFailStreak(), 1);
  eq('C10-h 失败后 failures 计数 +1', repo.queueStats().failures, failuresBefore + 1);
  ok('C10-i lastError 记录 FLUSH_FAILED 且带原因',
    repo.queueStats().lastError.indexOf('FLUSH_FAILED') >= 0,
    'lastError=' + repo.queueStats().lastError);
  ok('C10-j 失败后磁盘仍为空（flush 抛出，内存未落到磁盘）',
    FakePrefsControl.diskOf(STORE).size === 0,
    'actual=' + FakePrefsControl.diskOf(STORE).size);
  ok('C10-k 失败被诊断层记录（FLUSH_FAILED，ERROR 级）',
    repo.getDiagnostics().some((entry) => entry.code === 'FLUSH_FAILED' && entry.level === 'ERROR'),
    'codes=' + JSON.stringify(repo.getDiagnostics().map((entry) => entry.code)));

  // ══════════════════════════════════════════════════════════════════════════
  // C10b：连续 3 次失败 → failStreak = 3（达到 FLUSH_FAIL_WARN_STREAK 降级提示阈值）
  // ══════════════════════════════════════════════════════════════════════════
  FakePrefsControl.failFlush(1);
  const secondResult = await repo.flush();
  eq('C10b-a 第 2 次失败仍返回 STORAGE_ERROR', secondResult.code, 'STORAGE_ERROR');
  eq('C10b-b 第 2 次失败后 failStreak = 2', repo.storageFailStreak(), 2);

  FakePrefsControl.failFlush(1);
  const thirdResult = await repo.flush();
  eq('C10b-c 第 3 次失败仍返回 STORAGE_ERROR', thirdResult.code, 'STORAGE_ERROR');
  eq('C10b-d 第 3 次失败后 failStreak = 3（连续失败不因中途 write 成功而归零）',
    repo.storageFailStreak(), 3);
  eq('C10b-e 三次失败后 failures 累计 +3', repo.queueStats().failures, failuresBefore + 3);
  ok('C10b-f 三次失败后 10 个分区始终未被清掉',
    repo.dirtyPartitions().length === 10,
    'actual=' + JSON.stringify(repo.dirtyPartitions()));
  deepEq('C10b-g 三次失败期间内存态始终未变', repo.getState(), stateBefore);

  // ══════════════════════════════════════════════════════════════════════════
  // C10c：失败后成功 → streak 归零、pending 清空、磁盘出现数据
  // ══════════════════════════════════════════════════════════════════════════
  const recovered = await repo.flush();
  eq('C10c-a 恢复后返回 OK', recovered.code, 'OK');
  eq('C10c-b 恢复后 success = true', recovered.success, true);
  eq('C10c-c 恢复后 failStreak 归零', repo.storageFailStreak(), 0);
  eq('C10c-d 恢复后待写分区清空', repo.dirtyPartitions().length, 0);
  eq('C10c-e 恢复后 failures 累计值不再增长（保留历史 3 次）',
    repo.queueStats().failures, failuresBefore + 3);
  ok('C10c-f 恢复后磁盘有数据', FakePrefsControl.diskOf(STORE).size > 0,
    'actual=' + FakePrefsControl.diskOf(STORE).size);
  deepEq('C10c-g 恢复后内存态仍未变（写盘不反向改内存）', repo.getState(), stateBefore);

  // ══════════════════════════════════════════════════════════════════════════
  // L1：saveNowSync() 之后待写分区为空（onDestroy / onWindowStageDestroy 的收尾路径）
  // ══════════════════════════════════════════════════════════════════════════
  const diskAfterFlush = clone(Object.fromEntries(FakePrefsControl.diskOf(STORE)));

  repo.markDirty('SETTINGS');
  ok('L1-a markDirty(SETTINGS) 后 dirty 含 SETTINGS',
    repo.dirtyPartitions().indexOf('SETTINGS') >= 0,
    'actual=' + JSON.stringify(repo.dirtyPartitions()));

  const syncResult = repo.saveNowSync();
  eq('L1-b saveNowSync 返回 OK', syncResult.code, 'OK');
  eq('L1-c saveNowSync 后待写分区为空', repo.dirtyPartitions().length, 0);
  const diskAfterSync = Object.fromEntries(FakePrefsControl.diskOf(STORE));
  ok('L1-d saveNowSync 真的写到磁盘（SETTINGS 块头仍在）',
    typeof diskAfterSync['smartdorm.settings.hdr'] === 'string',
    'keys=' + JSON.stringify(Object.keys(diskAfterSync)));
  eq('L1-e saveNowSync 未改变已落盘的其他键数量',
    Object.keys(diskAfterSync).length, Object.keys(diskAfterFlush).length);

  // ══════════════════════════════════════════════════════════════════════════
  // 落盘键名形状（A6 前置 / 真机 `preferences` 文件可 grep 的依据）
  //   ① 11 把逻辑键 → 2 个标量键 + 9 个 `.hdr` + 每个 `.hdr` 对应 n 个 `.cNNNN`
  //   ② META 是标量分区，**不得**出现 `smartdorm.meta.schemaVersion.hdr`
  //   ③ 不得出现 4 位以外的块序号（`c1` / `c10000`）
  // ══════════════════════════════════════════════════════════════════════════
  const diskKeys = Object.keys(diskAfterSync);
  ok('K-a 落盘含 KEY-01 标量键', diskKeys.indexOf(StorageKeys.KEY_01_SCHEMA_VERSION) >= 0,
    'keys=' + JSON.stringify(diskKeys));
  ok('K-b 落盘含 KEY-11 标量键', diskKeys.indexOf(StorageKeys.KEY_11_RUNTIME) >= 0,
    'keys=' + JSON.stringify(diskKeys));
  eq('K-c KEY-01 的值是版本号 "1"',
    diskAfterSync[StorageKeys.KEY_01_SCHEMA_VERSION], '1');
  ok('K-d META 不产生块键（无 *.meta.*.hdr / *.meta.*.cNNNN）',
    diskKeys.every((key) => key.indexOf('meta.schemaVersion.') < 0 &&
      key.indexOf('meta.runtime.') < 0),
    'keys=' + JSON.stringify(diskKeys));
  ok('K-e 9 个分块基键各有且仅有一个 .hdr',
    StorageKeys.CHUNKED_BASES.every((base) =>
      diskKeys.filter((key) => key === base + '.hdr').length === 1),
    'keys=' + JSON.stringify(diskKeys));
  const counts = chunkCounts(diskKeys);
  ok('K-f 每个 .hdr 的 n 与真实块数一致',
    StorageKeys.CHUNKED_BASES.every((base) => {
      const raw = diskAfterSync[base + '.hdr'];
      if (typeof raw !== 'string') {
        return false;
      }
      const header = JSON.parse(raw);
      return (counts[base] || 0) === header.n;
    }),
    'counts=' + JSON.stringify(counts));
  ok('K-g 块的 JSON 含 p / i / t / d 四字段，t 为数字，且块数与 .hdr.n 一致',
    StorageKeys.CHUNKED_BASES.every((base) => {
      const raw = diskAfterSync[base + '.hdr'];
      if (typeof raw !== 'string') {
        return false;
      }
      const header = JSON.parse(raw);
      const n = header.n;
      if (n === 0) {
        // 空分区：不应写出任何 .cNNNN 块（n=0 时 encodePartition 不产块）
        return !diskKeys.some(function (k) { return k.indexOf(base + '.c') === 0; });
      }
      for (let i = 0; i < n; i++) {
        let digits = String(i);
        while (digits.length < 4) {
          digits = '0' + digits;
        }
        const cRaw = diskAfterSync[base + '.c' + digits];
        if (typeof cRaw !== 'string') {
          return false;
        }
        const chunk = JSON.parse(cRaw);
        if (StorageKeys.baseOfPartition(chunk.p) !== base) {
          return false;
        }
        if (chunk.i !== i || typeof chunk.t !== 'number' || !Array.isArray(chunk.d)) {
          return false;
        }
      }
      return true;
    }),
    'bases=' + JSON.stringify(StorageKeys.CHUNKED_BASES));
  ok('K-h 块头 JSON 含 p / n / t / v 四字段且 v = CHUNK_FORMAT_VERSION(1)',
    StorageKeys.CHUNKED_BASES.every((base) => {
      const header = JSON.parse(diskAfterSync[base + '.hdr']);
      return StorageKeys.baseOfPartition(header.p) === base && typeof header.n === 'number' &&
        typeof header.t === 'number' && header.v === 1;
    }),
    'bases=' + JSON.stringify(StorageKeys.CHUNKED_BASES));
  ok('K-i 键名长度均 ≤ MAX_KEY_LENGTH(80)',
    diskKeys.every((key) => key.length <= 80),
    'max=' + Math.max.apply(null, diskKeys.map((key) => key.length)));
  ok('K-j 每个 value 的字符数 ≤ MAX_VALUE_LENGTH(8192)（A6 的 L2 侧前置校验）',
    diskKeys.every((key) => diskAfterSync[key].length <= 8192),
    'max=' + Math.max.apply(null, diskKeys.map((key) => diskAfterSync[key].length)));

  // ══════════════════════════════════════════════════════════════════════════
  // 重启可读（模拟冷启动：内存回退到磁盘 → 新建仓储读回）
  //   本文件是进程级单例，无法真的重建；这里只证明「磁盘内容可被解码层读回」：
  //   直接用磁盘原文 + 仓储当前的 decode 路径不可达，改为断言磁盘 JSON 可解析且
  //   devices 块里含首启时的第一个设备 id——即「重新生成也不会相同的那个值」。
  // ══════════════════════════════════════════════════════════════════════════
  const deviceIdBefore = repo.getState().devices[0].id;
  ok('R-a 设备 id 出现在磁盘 devices 块原文里（不是只在内存）',
    diskAfterSync['smartdorm.devices.c0000'].indexOf(deviceIdBefore) >= 0,
    'id=' + deviceIdBefore);
  ok('R-b 创建时间戳出现在磁盘 devices 块原文里',
    diskAfterSync['smartdorm.devices.c0000'].indexOf(String(repo.getState().devices[0].createdAt)) >= 0,
    'createdAt=' + repo.getState().devices[0].createdAt);
  const runtimePersisted = JSON.parse(diskAfterSync[StorageKeys.KEY_11_RUNTIME]);
  eq('R-c 落盘的 bootCount 与内存一致', runtimePersisted.bootCount, 1);
  eq('R-d 落盘的 firstLaunchAt 与内存一致',
    runtimePersisted.firstLaunchAt, repo.getRuntimeMeta().firstLaunchAt);

  return summary('t403_repository');
}

main().then((allOk) => {
  process.exitCode = allOk ? 0 : 1;
}).catch((err) => {
  process.stdout.write('  FAIL  t403_repository 执行异常：' +
    (err && err.stack ? err.stack : String(err)) + '\n');
  process.exitCode = 1;
});

// `reset` 由 assert 导出，保留引用避免「未使用」告警语义混淆（本文件不复位计数）。
void reset;
