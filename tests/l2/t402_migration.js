/**
 * 智寓 · T4-02 判据 B7：SchemaMigration（L2）
 *
 * 覆盖：同版本直通、v0 → v1 链式迁移、版本倒退保留数据不降级、TARGET 与
 *       `SCHEMA_VERSION` 同源、缺失字段兜底、不修改入参对象。
 *
 * 运行：`node tests/l2/t402_migration.js`
 */
'use strict';

const { ok, eq, summary } = require('./assert');
const { SchemaMigration } = require('./.gen/out/store/SchemaMigration.js');
const { SCHEMA_VERSION } = require('./.gen/out/common/Constants.js');

const T0 = 1762700000000;

function baseState() {
  return {
    schemaVersion: 0,
    devices: [{ id: 'dev_light', name: '智能灯光', type: 'LIGHT', powerOn: false }],
    rules: [],
    scenes: [],
    settings: {
      automationEnabled: true,
      simulationEnabled: true,
      sampleIntervalMs: 4000,
      logLimit: 1000,
      schemaVersion: 0,
      appVersion: '1.0.0'
    },
    environment: {
      temperature: 25, humidity: 50, illuminance: 300, airQuality: 50,
      humanPresence: false, timestamp: T0, source: 'INIT'
    },
    logs: { operations: [], ruleExecutions: [], environment: [], sceneSwitches: [] },
    returnSnapshot: [],
    currentMode: 'MANUAL',
    currentSceneId: ''
  };
}

function main() {
  process.stdout.write('[B7] SchemaMigration\n');

  eq('TARGET === SCHEMA_VERSION（同源，不另立常量）',
    SchemaMigration.TARGET, SCHEMA_VERSION);

  // ——— 同版本直通 ———
  const same = baseState();
  const sameRes = SchemaMigration.migrate(same, SchemaMigration.TARGET);
  eq('migrate(state, 1).migrated === false', sameRes.migrated, false);
  eq("migrate(state, 1).error === ''", sameRes.error, '');
  eq('migrate(state, 1).toVersion === 1', sameRes.toVersion, 1);
  eq('migrate(state, 1).fromVersion === 1', sameRes.fromVersion, 1);
  ok('同版本返回同一对象（不做无谓拷贝）', sameRes.state === same);

  // ——— v0 → v1 ———
  const v0 = baseState();
  const up = SchemaMigration.migrate(v0, 0);
  eq('migrate(state, 0).toVersion === 1', up.toVersion, 1);
  eq('migrate(state, 0).fromVersion === 0', up.fromVersion, 0);
  eq('migrate(state, 0).migrated === true', up.migrated, true);
  eq("migrate(state, 0).error === ''", up.error, '');
  eq('迁移后 schemaVersion === 1', up.state.schemaVersion, 1);
  eq('迁移保留 devices 条数', up.state.devices.length, 1);
  eq('迁移不改入参对象（原 schemaVersion 仍为 0）', v0.schemaVersion, 0);

  // ——— 版本倒退：保留数据、不降级、error 非空 ———
  const ahead = baseState();
  const aheadRes = SchemaMigration.migrate(ahead, 99);
  eq('migrate(state, 99).migrated === false', aheadRes.migrated, false);
  ok('migrate(state, 99).error 非空', aheadRes.error.length > 0, aheadRes.error);
  eq('migrate(state, 99).toVersion === 1', aheadRes.toVersion, 1);
  eq('migrate(state, 99).fromVersion === 99', aheadRes.fromVersion, 99);
  eq('版本倒退时数据原样保留（条数不变）', aheadRes.state.devices.length, 1);
  eq('版本倒退时不改 schemaVersion（不得把旧数据标成新版本）',
    aheadRes.state.schemaVersion, 0);
  ok('版本倒退返回同一对象', aheadRes.state === ahead);

  // ——— v0 → v1 的字段兜底（磁盘旧数据可能整段缺失）———
  const broken = {
    schemaVersion: 0,
    devices: undefined,
    rules: undefined,
    scenes: undefined,
    returnSnapshot: undefined,
    settings: undefined,
    environment: undefined,
    logs: undefined,
    currentMode: 'NOT_A_MODE',
    currentSceneId: undefined
  };
  const fixed = SchemaMigration.migrateV0ToV1(broken);
  eq('devices 缺失 → []', fixed.devices.length, 0);
  eq('rules 缺失 → []', fixed.rules.length, 0);
  eq('scenes 缺失 → []', fixed.scenes.length, 0);
  eq('returnSnapshot 缺失 → []', fixed.returnSnapshot.length, 0);
  eq('logs 缺失 → 四个数组都补齐',
    fixed.logs.operations.length + fixed.logs.ruleExecutions.length +
    fixed.logs.environment.length + fixed.logs.sceneSwitches.length, 0);
  eq('settings 缺失 → 默认采样间隔 4000', fixed.settings.sampleIntervalMs, 4000);
  eq('settings 缺失 → 默认日志上限 1000', fixed.settings.logLimit, 1000);
  eq('environment 缺失 → 默认温度 25', fixed.environment.temperature, 25);
  eq('currentMode 非法 → MANUAL', fixed.currentMode, 'MANUAL');
  eq("currentSceneId 缺失 → ''", fixed.currentSceneId, '');
  eq('schemaVersion 补齐为 1', fixed.schemaVersion, 1);

  // 合法数据不被删：迁移期删数据是不可逆伤害
  const keep = baseState();
  keep.logs.ruleExecutions = [{
    id: 'rex_1', timestamp: T0, ruleId: 'rule_1', ruleName: 'n'
  }];
  keep.currentMode = 'SLEEP';
  keep.currentSceneId = 'scn_9';
  const kept = SchemaMigration.migrateV0ToV1(keep);
  eq('迁移不删合法执行日志', kept.logs.ruleExecutions.length, 1);
  eq('迁移保留合法 currentMode', kept.currentMode, 'SLEEP');
  eq('迁移保留 currentSceneId', kept.currentSceneId, 'scn_9');

  return summary('B7');
}

process.exitCode = main() ? 0 : 1;
