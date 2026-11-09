/**
 * 智寓 · L2 断言：6 个 L2 主判定用例（业务逻辑纯函数内核）
 *
 * 覆盖阶段五 §2.3 / §2.4 中以 L2 为主判定层的 6 个用例：
 *   TC-B-01 阈值边界不触发        → RuleMatcher.matchConditions（温度恰 28，规则 GT 28）
 *   TC-B-02 阈值边界触发          → RuleMatcher.matchConditions（温度 28.1）
 *   TC-B-03 参数上下界            → ParamSchema.validateParamValue（8 组边界值）
 *   TC-B-06 条件持续成立去重      → RuleMatcher.isEdgeTriggered / nextDedupFlag（连续 5 轮）
 *   TC-E-03 非法参数              → ParamSchema.validateParamValue（3 组越界值）
 *   TC-E-06 多规则同设备冲突      → WriteGuard.claim + RuleMatcher.sortRules（确定性排序）
 *
 * 这些函数零 `@kit.*` 依赖，已在 Node 侧经 DevEco 自带 tsc 编译（见 run.js），
 * 直接 require 生成产物即可；不引入任何第二实现（断言的就是产品代码）。
 *
 * 用法：`node tests/l2/t405_business.js`（通常由 `run.js` 调用）。
 */
'use strict';

require('./kit_alias');

const { ok, eq, summary, reset } = require('./assert');

const { RuleMatcher } = require('./.gen/out/service/RuleMatcher');
// 注：`ParamSchema.ets` 导出的是零散函数（validateParamValue / validateParam / ...），
// 不是 class，故取整个模块对象后通过点号调用。
const ParamSchema = require('./.gen/out/common/ParamSchema');
const { WriteGuard } = require('./.gen/out/service/WriteGuard');
const { Operator, SensorType, ParamKey, ResultCode, EnvSource } = require('./.gen/out/model/Enums');

/** 构造一条单一阈值条件。 */
function cond(sensorType, operator, threshold) {
  return {
    id: 'cond_' + sensorType + '_' + operator,
    sensorType: sensorType,
    operator: operator,
    threshold: threshold,
    unit: sensorType === SensorType.TEMPERATURE ? '℃' : ''
  };
}

/** 构造最小规则（condition 决定命中，priority/createdAt/id 决定排序）。 */
function rule(id, priority, createdAt, conditions) {
  return {
    id: id,
    name: id,
    enabled: true,
    logic: 'AND',
    conditions: conditions,
    actions: [],
    priority: priority,
    lastSatisfied: false,
    lastTriggeredAt: 0,
    executionCount: 0,
    createdAt: createdAt,
    updatedAt: createdAt
  };
}

/** 构造环境读数。 */
function env(temperature, humanPresence) {
  return {
    temperature: temperature,
    humidity: 50,
    illuminance: 300,
    airQuality: 50,
    humanPresence: humanPresence,
    timestamp: 0,
    source: EnvSource.MANUAL
  };
}

function main() {
  // ══════════════════════════════════════════════════════════════════════════
  // TC-B-01：阈值边界不触发（温度恰 28，规则「大于 28」）
  // ══════════════════════════════════════════════════════════════════════════
  const ruleGt28 = rule('r_gt28', 5, 100, [cond(SensorType.TEMPERATURE, Operator.GT, 28)]);
  const envAt28 = env(28, true);
  eq('TC-B-01-a matchConditions(28℃, >28) 返回 false',
    RuleMatcher.matchConditions(ruleGt28, envAt28), false);
  eq('TC-B-01-b matchedConditions(28℃) 长度为 0',
    RuleMatcher.matchedConditions(ruleGt28, envAt28).length, 0);

  // ══════════════════════════════════════════════════════════════════════════
  // TC-B-02：阈值边界触发（温度 28.1）
  // ══════════════════════════════════════════════════════════════════════════
  const envAt281 = env(28.1, true);
  eq('TC-B-02-a matchConditions(28.1℃, >28) 返回 true',
    RuleMatcher.matchConditions(ruleGt28, envAt281), true);
  eq('TC-B-02-b matchedConditions(28.1℃) 长度为 1',
    RuleMatcher.matchedConditions(ruleGt28, envAt281).length, 1);

  // ══════════════════════════════════════════════════════════════════════════
  // TC-B-03：参数上下界（8 组边界值全部允许写入）
  // ══════════════════════════════════════════════════════════════════════════
  const boundaryCases = [
    [ParamKey.BRIGHTNESS, 0],
    [ParamKey.BRIGHTNESS, 100],
    [ParamKey.TEMPERATURE, 16],
    [ParamKey.TEMPERATURE, 30],
    [ParamKey.OPEN_PERCENT, 0],
    [ParamKey.OPEN_PERCENT, 100],
    [ParamKey.FAN_SPEED, 1],
    [ParamKey.FAN_SPEED, 3]
  ];
  for (const [key, value] of boundaryCases) {
    eq('TC-B-03 ' + key + '=' + value + ' → ResultCode.OK',
      ParamSchema.validateParamValue(key, value), ResultCode.OK);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TC-B-06：条件持续成立去重（连续 5 个采样周期仅执行 1 次）
  //   仅 false→true 触发一次；之后持续满足不再触发。
  // ══════════════════════════════════════════════════════════════════════════
  let lastSatisfied = false;
  const satisfied = true;
  const edgeResults = [];
  for (let i = 0; i < 5; i++) {
    edgeResults.push(RuleMatcher.isEdgeTriggered(lastSatisfied, satisfied));
    lastSatisfied = RuleMatcher.nextDedupFlag(lastSatisfied, satisfied);
  }
  eq('TC-B-06-a 第 1 轮（false→true）边沿触发为 true', edgeResults[0], true);
  ok('TC-B-06-b 第 2~5 轮（true→true）均不再触发',
    edgeResults[1] === false && edgeResults[2] === false &&
    edgeResults[3] === false && edgeResults[4] === false,
    'edgeResults=' + JSON.stringify(edgeResults));
  eq('TC-B-06-c 5 轮后 nextDedupFlag 仍为 true（lastSatisfied 持续成立）',
    lastSatisfied, true);

  // ══════════════════════════════════════════════════════════════════════════
  // TC-E-03：非法参数（3 组越界值拒绝写入）
  // ══════════════════════════════════════════════════════════════════════════
  const invalidCases = [
    [ParamKey.BRIGHTNESS, 150],
    [ParamKey.TEMPERATURE, 99],
    [ParamKey.FAN_SPEED, 9]
  ];
  for (const [key, value] of invalidCases) {
    eq('TC-E-03 ' + key + '=' + value + ' → ResultCode.INVALID_PARAM',
      ParamSchema.validateParamValue(key, value), ResultCode.INVALID_PARAM);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TC-E-06：多规则同设备冲突（WriteGuard 先到先得 + sortRules 确定性排序）
  // ══════════════════════════════════════════════════════════════════════════
  const DEV = 'dev_light_1';
  const guard = new WriteGuard();
  guard.reset();
  eq('TC-E-06-a 首个 (device,paramKey) 申请写入权返回 true',
    guard.claim(DEV, ParamKey.BRIGHTNESS, 'ruleA'), true);
  eq('TC-E-06-b 同 (device,paramKey) 被本轮其他规则占用返回 false',
    guard.claim(DEV, ParamKey.BRIGHTNESS, 'ruleB'), false);
  eq('TC-E-06-c 本轮登记明细仅 1 条', guard.entries().length, 1);
  eq('TC-E-06-d 不同 (device,paramKey) 仍可申请（不受同设备其它键影响）',
    guard.claim(DEV, ParamKey.OPEN_PERCENT, 'ruleC'), true);

  // 确定性排序：priority → createdAt → id
  const rA = rule('rule_A', 5, 100, []);
  const rB = rule('rule_B', 5, 200, []);
  const rC = rule('rule_C', 5, 200, []);
  const sortedByCreated = RuleMatcher.sortRules([rB, rA]);
  eq('TC-E-06-e sortRules 按 createdAt 升序（priority 相同）',
    sortedByCreated[0].id + '|' + sortedByCreated[1].id, 'rule_A|rule_B');
  const sortedById = RuleMatcher.sortRules([rC, rB]);
  eq('TC-E-06-f sortRules 按 id 字典序（priority/createdAt 相同）',
    sortedById[0].id + '|' + sortedById[1].id, 'rule_B|rule_C');
  const sortedByPriority = RuleMatcher.sortRules([rule('rule_X', 9, 999, []), rA]);
  eq('TC-E-06-g sortRules 按 priority 升序（小者优先）',
    sortedByPriority[0].id + '|' + sortedByPriority[1].id, 'rule_A|rule_X');

  return summary('t405_business');
}

try {
  const allOk = main();
  process.exitCode = allOk ? 0 : 1;
} catch (err) {
  process.stdout.write('  FAIL  t405_business 执行异常：' +
    (err && err.stack ? err.stack : String(err)) + '\n');
  process.exitCode = 1;
}

void reset;
