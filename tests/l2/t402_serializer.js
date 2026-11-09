/**
 * 智寓 · T4-02 判据 B2/B3/B4/B5/B6/B9/B10/B11/B12/B13 + E1/E2：Serializer（L2）
 *
 * 全部断言都打真实函数，不 mock 被测对象；只有「块字符串」由被测的
 * `encodePartition` / `encodeHeader` 生成，避免测试自己造一套格式而与实现漂移。
 *
 * 运行：`node tests/l2/t402_serializer.js`（先由 run.js 生成 .gen 并编译）
 */
'use strict';

const { ok, eq, deepEq, summary } = require('./assert');
const { Serializer } = require('./.gen/out/store/Serializer.js');
const { StoragePartition } = require('./.gen/out/store/StorageKeys.js');
const { StorageDiagnostics } = require('./.gen/out/store/StorageDiagnostics.js');
const { CHUNK_MAX_CHARS, ENTRY_GUARD_CHARS } = require('./.gen/out/common/Constants.js');

const T0 = 1762700000000;
const ENV_LOGS = StoragePartition.ENVIRONMENT_LOGS;
const DEVICES = StoragePartition.DEVICES;

// ——————————————————————————————————————————————————————————————
// 数据构造
// ——————————————————————————————————————————————————————————————

function envLog(i) {
  return {
    id: 'env_' + i,
    timestamp: T0 + i,
    sensorType: 'TEMPERATURE',
    before: 20 + (i % 5),
    after: 21 + (i % 5),
    source: 'SIMULATED'
  };
}

/** 构造一条「JSON.stringify 后恰好 len 个字符」的 EnvironmentLog（用于 E1/E2 边界）。 */
const ENV_LOG_SHELL_LEN = JSON.stringify(envLog(0)).length - envLog(0).id.length;

function envLogOfLen(len, seed) {
  const log = envLog(seed === undefined ? 0 : seed);
  const idLen = len - ENV_LOG_SHELL_LEN;
  let id = '';
  while (id.length < idLen) {
    id = id + 'x';
  }
  log.id = id;
  return log;
}

function emptyState() {
  return {
    schemaVersion: 1,
    devices: [],
    rules: [],
    scenes: [],
    settings: {
      automationEnabled: true,
      simulationEnabled: true,
      sampleIntervalMs: 4000,
      logLimit: 1000,
      schemaVersion: 1,
      appVersion: '1.0.0'
    },
    environment: {
      temperature: 25,
      humidity: 50,
      illuminance: 300,
      airQuality: 50,
      humanPresence: false,
      timestamp: T0,
      source: 'INIT'
    },
    logs: { operations: [], ruleExecutions: [], environment: [], sceneSwitches: [] },
    returnSnapshot: [],
    currentMode: 'MANUAL',
    currentSceneId: ''
  };
}

function device(type) {
  const params = {
    LIGHT: { kind: 'LIGHT', brightness: 60 },
    AIR_CONDITIONER: { kind: 'AIR_CONDITIONER', temperature: 26, mode: 'AUTO' },
    CURTAIN: { kind: 'CURTAIN', openPercent: 0 },
    DOOR_LOCK: { kind: 'DOOR_LOCK', locked: true },
    FAN: { kind: 'FAN', fanSpeed: 1 },
    SOCKET: { kind: 'SOCKET', powerWatt: 0 }
  }[type];
  return {
    id: 'dev_' + type.toLowerCase(),
    name: '设备-' + type,
    type: type,
    powerOn: false,
    params: params,
    online: true,
    status: 'IDLE',
    locked: type === 'DOOR_LOCK',
    createdAt: T0,
    lastUpdated: T0 + 1
  };
}

function snapshot(deviceId) {
  return {
    deviceId: deviceId,
    powerOn: true,
    params: { kind: 'LIGHT', brightness: 80 },
    locked: false,
    online: true,
    status: 'RUNNING',
    capturedAt: T0
  };
}

function rule() {
  return {
    id: 'rule_1',
    name: '温度高了开空调',
    enabled: true,
    logic: 'AND',
    conditions: [
      { id: 'cond_1', sensorType: 'TEMPERATURE', operator: 'GT', threshold: 26, unit: 'C' },
      { id: 'cond_2', sensorType: 'HUMAN_PRESENCE', operator: 'IS_TRUE', threshold: 0, unit: '' }
    ],
    actions: [
      { id: 'act_1', targetDeviceId: 'dev_air_conditioner', command: 'POWER_ON', value: true, order: 1 },
      { id: 'act_2', targetDeviceId: 'dev_air_conditioner', command: 'SET_MODE', value: 'COOL', order: 2 }
    ],
    priority: 1,
    lastSatisfied: true,
    lastTriggeredAt: T0 + 5,
    executionCount: 3,
    createdAt: T0,
    updatedAt: T0 + 5
  };
}

function scene() {
  return {
    id: 'scn_1',
    name: '学习模式',
    type: 'STUDY',
    deviceStates: [snapshot('dev_light')],
    isPreset: true,
    returnSnapshot: [snapshot('dev_light')],
    createdAt: T0,
    updatedAt: T0
  };
}

function operationLog(i) {
  return {
    id: 'op_' + i,
    timestamp: T0 + i,
    actor: 'USER',
    deviceId: 'dev_light',
    action: 'SET_BRIGHTNESS',
    before: '{"brightness":60}',
    after: '{"brightness":80}',
    result: 'OK',
    message: '亮度 60% → 80%'
  };
}

function ruleExecLog(i) {
  return {
    id: 'rex_' + i,
    timestamp: T0 + i,
    ruleId: 'rule_1',
    ruleName: '温度高了开空调',
    snapshot: {
      temperature: 30,
      humidity: 55,
      illuminance: 400,
      airQuality: 60,
      humanPresence: true,
      timestamp: T0 + i,
      source: 'SIMULATED'
    },
    matchedConditions: [
      { id: 'cond_1', sensorType: 'TEMPERATURE', operator: 'GT', threshold: 26, unit: 'C' }
    ],
    executedActions: [
      {
        actionId: 'act_1', targetDeviceId: 'dev_air_conditioner', command: 'POWER_ON',
        value: 'true', result: 'OK', message: '已开机'
      }
    ],
    skippedActions: [],
    status: 'SUCCESS',
    errorMsg: '',
    durationMs: 12
  };
}

function sceneSwitchLog(i) {
  return {
    id: 'sw_' + i,
    timestamp: T0 + i,
    fromSceneId: '',
    toSceneId: 'scn_1',
    appliedCount: 3,
    failedCount: 0
  };
}

function fullState() {
  const state = emptyState();
  state.devices = [
    device('LIGHT'), device('AIR_CONDITIONER'), device('CURTAIN'),
    device('DOOR_LOCK'), device('FAN'), device('SOCKET')
  ];
  state.rules = [rule()];
  state.scenes = [scene()];
  state.logs.sceneSwitches = [sceneSwitchLog(1), sceneSwitchLog(2)];
  state.logs.operations = [operationLog(1), operationLog(2)];
  state.logs.ruleExecutions = [ruleExecLog(1)];
  state.returnSnapshot = [snapshot('dev_light')];
  return state;
}

function encode(state, partition) {
  return Serializer.encodePartition(partition, state);
}

// ——————————————————————————————————————————————————————————————
// 用例
// ——————————————————————————————————————————————————————————————

function caseB2() {
  process.stdout.write('[B2] 2000 条环境日志：块长上限与逐条往返\n');
  StorageDiagnostics.getInstance().clear();
  const state = emptyState();
  for (let i = 0; i < 2000; i++) {
    state.logs.environment.push(envLog(i));
  }
  const encoded = encode(state, ENV_LOGS);
  eq('分块生效（块数 > 1）', encoded.chunks.length > 1, true);
  let maxLen = 0;
  for (const chunk of encoded.chunks) {
    if (chunk.length > maxLen) {
      maxLen = chunk.length;
    }
  }
  ok('每一块 length <= CHUNK_MAX_CHARS(' + CHUNK_MAX_CHARS + ')', maxLen <= CHUNK_MAX_CHARS,
    'max=' + maxLen + ' chunks=' + encoded.chunks.length);
  eq('totalEntries = 2000', encoded.totalEntries, 2000);
  eq('droppedEntries = 0', encoded.droppedEntries, 0);
  eq('error 为空', encoded.error, '');
  eq('块头 n = 块数', encoded.header.n, encoded.chunks.length);

  const decoded = Serializer.decodeEnvironmentLogs(encoded.chunks);
  eq('解码 ok', decoded.ok, true);
  eq('解码条数 = 2000', decoded.data.length, 2000);
  eq('解码 dropped = 0', decoded.dropped, 0);
  deepEq('2000 条逐条逐字段相等（顺序不变）', decoded.data, state.logs.environment);
  return encoded;
}

function caseB3andE1() {
  process.stdout.write('[B3/E1] 单条守卫边界（6500 / 6501 / 7000 字符）\n');
  StorageDiagnostics.getInstance().clear();

  // E1：恰好 6500 保留、6501 丢弃
  const keep = envLogOfLen(6500, 1);
  const drop = envLogOfLen(6501, 2);
  eq('E1 构造条目长度 6500', JSON.stringify(keep).length, 6500);
  eq('E1 构造条目长度 6501', JSON.stringify(drop).length, 6501);
  const stateE1 = emptyState();
  stateE1.logs.environment = [keep, drop];
  const encE1 = encode(stateE1, ENV_LOGS);
  eq('E1 droppedEntries = 1（只有 6501 被丢）', encE1.droppedEntries, 1);
  eq('E1 totalEntries = 2', encE1.totalEntries, 2);
  const decE1 = Serializer.decodeEnvironmentLogs(encE1.chunks);
  eq('E1 解码条数 = 1', decE1.data.length, 1);
  eq('E1 保留的是 6500 那条', JSON.stringify(decE1.data[0]).length, 6500);

  // B3：混 1 条 7000 字符 → 丢它，其余完整
  StorageDiagnostics.getInstance().clear(); // E1 也产生过 1 条，这里单独统计
  const stateB3 = emptyState();
  stateB3.logs.environment = [envLog(1), envLogOfLen(7000, 9), envLog(2)];
  const encB3 = encode(stateB3, ENV_LOGS);
  eq('B3 droppedEntries = 1', encB3.droppedEntries, 1);
  eq('B3 totalEntries = 3', encB3.totalEntries, 3);
  const decB3 = Serializer.decodeEnvironmentLogs(encB3.chunks);
  eq('B3 解码 ok', decB3.ok, true);
  eq('B3 其余 2 条完整', decB3.data.length, 2);
  deepEq('B3 内容是原第 1、3 条', decB3.data, [envLog(1), envLog(2)]);
  ok('B3 产生 ENTRY_DROPPED 诊断',
    StorageDiagnostics.getInstance().list().filter((e) => e.code === 'ENTRY_DROPPED').length === 1,
    '诊断条数=' + StorageDiagnostics.getInstance().size());
}

function caseE2() {
  process.stdout.write('[E2] 块边界：恰好填满 vs 溢出 1 字符\n');
  StorageDiagnostics.getInstance().clear();
  const L = 200; // 必须大于「一条日志除 id 之外的固定开销」，否则 id 会被压成空串
  eq('E2 单条构造长度 = ' + L, JSON.stringify(envLogOfLen(L, 0)).length, L);
  // 用真实编码找「一块最多能装几条」，不自己算块头开销（开销随 i 位数变化）
  let count = 1;
  let limit = 0;
  while (count <= 400) {
    const probe = emptyState();
    for (let i = 0; i < count; i++) {
      probe.logs.environment.push(envLogOfLen(L, i));
    }
    if (encode(probe, ENV_LOGS).chunks.length > 1) {
      limit = count - 1;
      break;
    }
    count += 1;
  }
  ok('探测到「一块最多 ' + limit + ' 条」的边界', limit > 0, 'limit=' + limit);

  const exact = emptyState();
  for (let i = 0; i < limit; i++) {
    exact.logs.environment.push(envLogOfLen(L, i));
  }
  const encExact = encode(exact, ENV_LOGS);
  eq('恰好装下的条数 → 1 块', encExact.chunks.length, 1);
  const decExact = Serializer.decodeEnvironmentLogs(encExact.chunks);
  eq('恰好装下 → 全部条目往返', decExact.data.length, limit);
  const slack = CHUNK_MAX_CHARS - encExact.chunks[0].length;

  // 把最后一条加长 slack，使块长**正好等于** CHUNK_MAX_CHARS（用一个字节都不浪费）
  const fill = emptyState();
  for (let i = 0; i < limit - 1; i++) {
    fill.logs.environment.push(envLogOfLen(L, i));
  }
  fill.logs.environment.push(envLogOfLen(L + slack, limit - 1));
  const encFill = encode(fill, ENV_LOGS);
  eq('补满 slack 后仍是 1 块', encFill.chunks.length, 1);
  eq('补满后块长正好 = CHUNK_MAX_CHARS', encFill.chunks[0].length, CHUNK_MAX_CHARS);
  eq('补满后条目全部往返', Serializer.decodeEnvironmentLogs(encFill.chunks).data.length, limit);

  // 再多 1 个字符 → 溢出到 2 块
  const overflow = emptyState();
  for (let i = 0; i < limit - 1; i++) {
    overflow.logs.environment.push(envLogOfLen(L, i));
  }
  overflow.logs.environment.push(envLogOfLen(L + slack + 1, limit - 1));
  const encOverflow = encode(overflow, ENV_LOGS);
  eq('再多 1 个字符 → 2 块', encOverflow.chunks.length, 2);
  const decOverflow = Serializer.decodeEnvironmentLogs(encOverflow.chunks);
  eq('2 块拼回条数不变', decOverflow.data.length, limit);
  deepEq('2 块拼回顺序不变', decOverflow.data, overflow.logs.environment);
  ok('2 块拼回后每块仍 ≤ CHUNK_MAX_CHARS',
    encOverflow.chunks.every((c) => c.length <= CHUNK_MAX_CHARS),
    'lens=' + encOverflow.chunks.map((c) => c.length).join(','));
  eq('溢出块只装 1 条', encOverflow.chunks[1].split('"id"').length - 1, 1);
}

function caseRoundTripAll() {
  process.stdout.write('[往返] 每个分区都编码→解码逐字段相等\n');
  StorageDiagnostics.getInstance().clear();
  const state = fullState();

  const devices = encode(state, StoragePartition.DEVICES);
  const devicesBack = Serializer.decodeDevices(devices.chunks);
  eq('DEVICES ok', devicesBack.ok, true);
  deepEq('DEVICES 往返', devicesBack.data, state.devices);

  const rules = encode(state, StoragePartition.RULES);
  const rulesBack = Serializer.decodeRules(rules.chunks);
  eq('RULES ok', rulesBack.ok, true);
  deepEq('RULES 往返（含 lastSatisfied）', rulesBack.data, state.rules);

  const scenes = encode(state, StoragePartition.SCENES);
  const scenesBack = Serializer.decodeScenes(scenes.chunks);
  eq('SCENES ok', scenesBack.ok, true);
  deepEq('SCENES 往返（scenes）', scenesBack.data.scenes, state.scenes);
  deepEq('SCENES 往返（sceneSwitches 同区）', scenesBack.data.sceneSwitches,
    state.logs.sceneSwitches);

  const settings = encode(state, StoragePartition.SETTINGS);
  const settingsBack = Serializer.decodeSettings(settings.chunks);
  eq('SETTINGS ok', settingsBack.ok, true);
  deepEq('SETTINGS 往返（单对象单元素数组）', settingsBack.data, state.settings);
  eq('SETTINGS 单块单条', settings.chunks.length, 1);

  const environment = encode(state, StoragePartition.ENVIRONMENT);
  const environmentBack = Serializer.decodeEnvironment(environment.chunks);
  eq('ENVIRONMENT ok', environmentBack.ok, true);
  deepEq('ENVIRONMENT 往返', environmentBack.data, state.environment);

  const ops = encode(state, StoragePartition.OPERATION_LOGS);
  const opsBack = Serializer.decodeOperationLogs(ops.chunks);
  deepEq('OPERATION_LOGS 往返', opsBack.data, state.logs.operations);

  const execs = encode(state, StoragePartition.RULE_EXEC_LOGS);
  const execsBack = Serializer.decodeRuleExecLogs(execs.chunks);
  eq('RULE_EXEC_LOGS ok', execsBack.ok, true);
  deepEq('RULE_EXEC_LOGS 往返（含 snapshot/动作明细）', execsBack.data, state.logs.ruleExecutions);

  const snaps = encode(state, StoragePartition.RETURN_SNAPSHOT);
  const snapsBack = Serializer.decodeReturnSnapshot(snaps.chunks);
  eq('RETURN_SNAPSHOT ok', snapsBack.ok, true);
  deepEq('RETURN_SNAPSHOT 往返', snapsBack.data, state.returnSnapshot);

  // META 不走 encodePartition
  const meta = encode(state, StoragePartition.META);
  eq('META 拒绝经 encodePartition', meta.error.length > 0, true);
  eq('META 无块', meta.chunks.length, 0);

  // KEY-11 运行时元信息往返
  const runtime = {
    currentSceneId: 'scn_1', currentMode: 'STUDY',
    firstLaunchAt: T0, lastLaunchAt: T0 + 100, bootCount: 7
  };
  const runtimeRaw = Serializer.encodeRuntime(runtime);
  const runtimeBack = Serializer.decodeRuntime(runtimeRaw);
  eq('decodeRuntime ok', runtimeBack.ok, true);
  deepEq('RuntimeMeta 往返', runtimeBack.data, runtime);
  const defaultMeta = Serializer.defaultRuntime(T0);
  eq('defaultRuntime bootCount = 1', defaultMeta.bootCount, 1);
  eq('defaultRuntime currentMode = MANUAL', defaultMeta.currentMode, 'MANUAL');
  eq('defaultRuntime firstLaunchAt = now', defaultMeta.firstLaunchAt, T0);
}

function caseB4B9B10B11B13(bigEncode) {
  process.stdout.write('[B4/B9/B10/B11/B13] 块数与块头一致性（1.1.3 ①②③④）\n');
  const header = Serializer.encodeHeader(bigEncode.header);
  const chunkCount = bigEncode.chunks.length;
  ok('前置：至少 5 块可用', chunkCount >= 5, 'chunks=' + chunkCount);

  // B4：删掉中间一块
  const broken = bigEncode.chunks.filter((_c, i) => i !== 1);
  const resB4 = Serializer.assemblePartition(ENV_LOGS, header, broken,
    Serializer.decodeEnvironmentLogs);
  eq('B4 ok = false', resB4.ok, false);
  ok('B4 error 非空', resB4.error.length > 0, resB4.error);
  eq('B4 data 不返回', resB4.data, undefined);

  // B9：块头 n=5 但只给 4 块
  const header5 = Serializer.encodeHeader({ p: ENV_LOGS, n: 5, t: T0, v: 1 });
  const resB9 = Serializer.assemblePartition(ENV_LOGS, header5, bigEncode.chunks.slice(0, 4),
    Serializer.decodeEnvironmentLogs);
  eq('B9 ok = false（缺块＝损坏）', resB9.ok, false);
  ok('B9 error 含 CHUNK_MISSING', resB9.error.indexOf('CHUNK_MISSING') >= 0, resB9.error);

  // B10：块头 n=3 但给 5 块（尾部 2 个孤儿）
  StorageDiagnostics.getInstance().clear();
  const header3 = Serializer.encodeHeader({ p: ENV_LOGS, n: 3, t: T0, v: 1 });
  const resB10 = Serializer.assemblePartition(ENV_LOGS, header3, bigEncode.chunks.slice(0, 5),
    Serializer.decodeEnvironmentLogs);
  eq('B10 ok = true（多余块不判损坏）', resB10.ok, true);
  eq('B10 error 为空', resB10.error, '');
  const infoList = StorageDiagnostics.getInstance().list().filter((e) => e.level === 'INFO' &&
    e.code === 'EXTRA_CHUNK');
  eq('B10 产生 1 条 INFO 诊断', infoList.length, 1);
  ok('B10 诊断细节含孤儿块数', infoList.length === 1 && infoList[0].detail.indexOf('2') >= 0,
    infoList.length === 1 ? infoList[0].detail : '');
  // 只解析前 3 块：条数应少于全部
  const resB10Full = Serializer.assemblePartition(ENV_LOGS, header,
    bigEncode.chunks, Serializer.decodeEnvironmentLogs);
  ok('B10 只解析前 3 块（条数 < 全量）', resB10.data.length < resB10Full.data.length,
    '3块=' + resB10.data.length + ' 全量=' + resB10Full.data.length);

  // B11：块头缺失但有块
  const resB11 = Serializer.assemblePartition(ENV_LOGS, '', bigEncode.chunks,
    Serializer.decodeEnvironmentLogs);
  eq('B11 ok = false（有块无头）', resB11.ok, false);
  ok('B11 error 含 HEADER_MISSING', resB11.error.indexOf('HEADER_MISSING') >= 0, resB11.error);

  // B13：块头 v=2
  const headerV2 = Serializer.encodeHeader({ p: ENV_LOGS, n: 1, t: T0, v: 2 });
  const resB13 = Serializer.assemblePartition(ENV_LOGS, headerV2, bigEncode.chunks.slice(0, 1),
    Serializer.decodeEnvironmentLogs);
  eq('B13 ok = false（不猜未来格式）', resB13.ok, false);
  ok('B13 error 含 HEADER_VERSION', resB13.error.indexOf('HEADER_VERSION') >= 0, resB13.error);

  // 额外：空分区（无头无块）
  const resEmpty = Serializer.assemblePartition(ENV_LOGS, '', [], Serializer.decodeEnvironmentLogs);
  eq('空分区 ok = false 且 error 以 EMPTY 开头', resEmpty.error.indexOf('EMPTY') === 0, true);
  ok('EMPTY 与 HEADER_MISSING 可区分（调用方据此判「首次启动」vs「损坏」）',
    resEmpty.error !== resB11.error);
}

function caseB5() {
  process.stdout.write('[B5] 损坏 JSON / 类型不符 / 缺字段：逐分区独立\n');
  StorageDiagnostics.getInstance().clear();
  const state = fullState();
  const devicesChunks = encode(state, StoragePartition.DEVICES).chunks;

  const badJson = Serializer.decodeDevices(['{not json']);
  eq('坏 JSON → ok false', badJson.ok, false);
  ok('坏 JSON → error 非空', badJson.error.length > 0, badJson.error);

  const wrongType = Serializer.decodeDevices([
    '{"p":"DEVICES","i":0,"t":1,"d":[{"id":123,"name":"x","type":"LIGHT","powerOn":false,' +
    '"params":{"kind":"LIGHT","brightness":60},"online":true,"status":"IDLE","locked":false,' +
    '"createdAt":1,"lastUpdated":1}]}'
  ]);
  eq('字段类型不符（id 是数字）→ ok false', wrongType.ok, false);

  const missingField = Serializer.decodeDevices([
    '{"p":"DEVICES","i":0,"t":1,"d":[{"id":"dev_x","type":"LIGHT","powerOn":false,' +
    '"params":{"kind":"LIGHT","brightness":60},"online":true,"status":"IDLE","locked":false,' +
    '"createdAt":1,"lastUpdated":1}]}'
  ]);
  eq('缺字段（无 name）→ ok false', missingField.ok, false);

  const kindMismatch = Serializer.decodeDevices([
    '{"p":"DEVICES","i":0,"t":1,"d":[{"id":"dev_x","name":"x","type":"LIGHT","powerOn":false,' +
    '"params":{"kind":"CURTAIN","openPercent":0},"online":true,"status":"IDLE","locked":false,' +
    '"createdAt":1,"lastUpdated":1}]}'
  ]);
  eq('params.kind 与 type 不一致 → ok false', kindMismatch.ok, false);

  const unknownEnum = Serializer.decodeDevices([
    '{"p":"DEVICES","i":0,"t":1,"d":[{"id":"dev_x","name":"x","type":"LIGHT","powerOn":false,' +
    '"params":{"kind":"LIGHT","brightness":60},"online":true,"status":"WEIRD","locked":false,' +
    '"createdAt":1,"lastUpdated":1}]}'
  ]);
  eq('未知枚举 status=WEIRD → ok false', unknownEnum.ok, false);

  const badRuleExec = Serializer.decodeRuleExecLogs([
    '{"p":"RULE_EXEC_LOGS","i":0,"t":1,"d":[{"id":"rex_1","timestamp":1,"ruleId":"r","ruleName":"n",' +
    '"snapshot":{},"matchedConditions":[],"executedActions":[],"skippedActions":[],' +
    '"status":"SUCCESS","errorMsg":"","durationMs":1}]}'
  ]);
  eq('RULE_EXEC_LOGS 坏一条 → ok false', badRuleExec.ok, false);

  // 逐分区独立：同一时刻 DEVICES 仍能读通
  const healthy = Serializer.decodeDevices(devicesChunks);
  eq('同时 DEVICES 仍 ok（互不牵连）', healthy.ok, true);
  eq('DEVICES 条数 6', healthy.data.length, 6);

  // 跨分区串块：把 DEVICES 的块喂给 RULES
  const crossFeed = Serializer.decodeRules(devicesChunks);
  eq('分区不匹配的块 → ok false', crossFeed.ok, false);
  ok('分区不匹配 error 含 CHUNK_PARTITION', crossFeed.error.indexOf('CHUNK_PARTITION') >= 0,
    crossFeed.error);
}

function caseB6() {
  process.stdout.write('[B6] decodeSchemaVersion\n');
  eq("decodeSchemaVersion('') = 0", Serializer.decodeSchemaVersion(''), 0);
  eq("decodeSchemaVersion('1') = 1", Serializer.decodeSchemaVersion('1'), 1);
  eq("decodeSchemaVersion('abc') = 0", Serializer.decodeSchemaVersion('abc'), 0);
  eq("decodeSchemaVersion('-1') = 0", Serializer.decodeSchemaVersion('-1'), 0);
  eq("decodeSchemaVersion('1.5') = 0", Serializer.decodeSchemaVersion('1.5'), 0);
  eq("decodeSchemaVersion('9999999999999') = 0", Serializer.decodeSchemaVersion('9999999999999'), 0);
  eq("decodeSchemaVersion('007') = 7（纯数字按数值）", Serializer.decodeSchemaVersion('007'), 7);
  eq("decodeSchemaVersion('12abc') = 0（不学 parseInt 的前缀截断）",
    Serializer.decodeSchemaVersion('12abc'), 0);
}

function caseB12() {
  process.stdout.write('[B12] 加载期守卫：块内混入 1 条超长条目\n');
  StorageDiagnostics.getInstance().clear();
  const hugeId = 'z'.repeat(CHUNK_MAX_CHARS);
  const raw = '{"p":"ENVIRONMENT_LOGS","i":0,"t":' + T0 + ',"d":[' +
    JSON.stringify(envLog(1)) + ',{"id":"' + hugeId + '","timestamp":' + T0 +
    ',"sensorType":"TEMPERATURE","before":0,"after":1,"source":"SIMULATED"}]}';
  ok('手工块长度已超过 CHUNK_MAX_CHARS（模拟旧版本写入的块）',
    raw.length > CHUNK_MAX_CHARS, 'len=' + raw.length);

  const header = Serializer.encodeHeader({ p: ENV_LOGS, n: 1, t: T0, v: 1 });
  const result = Serializer.assemblePartition(ENV_LOGS, header, [raw],
    Serializer.decodeEnvironmentLogs);
  eq('ok = true（守卫丢弃不算损坏）', result.ok, true);
  eq('dropped = 1', result.dropped, 1);
  eq('其余条目完整（1 条）', result.data.length, 1);
  deepEq('保留的是原第 1 条', result.data, [envLog(1)]);
  const skipped = StorageDiagnostics.getInstance().list().filter((e) => e.code === 'ENTRY_SKIPPED');
  eq('诊断里 ENTRY_SKIPPED 计数为 1', skipped.length, 1);
  eq('诊断级别 INFO（不是 ERROR/WARN）', skipped[0].level, 'INFO');
}

function main() {
  const bigEncode = caseB2();
  caseB3andE1();
  caseE2();
  caseRoundTripAll();
  caseB4B9B10B11B13(bigEncode);
  caseB5();
  caseB6();
  caseB12();
  return summary('B2/B3/B4/B5/B6/B9/B10/B11/B12/B13 + E1/E2');
}

process.exitCode = main() ? 0 : 1;
