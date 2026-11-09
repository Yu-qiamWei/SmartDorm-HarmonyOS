/**
 * 智寓 · schema 版本迁移（设计 8.6 步骤 5 / 任务列表-第四阶段 §1.3、§4.4）
 *
 * 职责：把「从磁盘读回的某个版本的 `AppState`」沿版本链逐级升到 `SCHEMA_VERSION`。
 * 纯函数：不改入参对象的字段语义之外的东西、不做 IO、不写 `KEY-01`。
 *
 * 三条硬规则（§1.3）：
 *   ① `fromVersion <  SCHEMA_VERSION` → `migrate_vN_to_vN+1` **逐级链式**，每级只做字段增删改与默认值补齐；
 *   ② `fromVersion === SCHEMA_VERSION` → 原样返回，`migrated = false`，`error = ''`；
 *   ③ `fromVersion >  SCHEMA_VERSION`（版本倒退，例如降级安装）→ **保留原数据**、不强行降级、
 *      `migrated = false`、`error` 非空（调用方据此**不得**写回 `KEY-01`，否则会把旧数据标成新版本）。
 *
 * 迁移失败一律「保留原数据 + 记诊断 + 以 decode 出的原态继续运行」（不崩溃、不重置）。
 *
 * 本类零系统 API 依赖（不 import 任何 Kit 模块），可在 Node 侧单测（判据 B7）。
 *
 * 依据：design/任务列表-第四阶段.md 1.3、4.4。
 */
import { AppState } from '../model/AppState';
import { AppSettings } from '../model/AppSettings';
import { EnvironmentData } from '../model/EnvironmentData';
import { LogBundle, OperationLog, RuleExecutionLog, EnvironmentLog, SceneSwitchLog } from '../model/Logs';
import { Device } from '../model/Device';
import { AutomationRule } from '../model/AutomationRule';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { EnvSource, RunMode } from '../model/Enums';
import {
  SCHEMA_VERSION, DEFAULT_SAMPLE_INTERVAL_MS, DEFAULT_LOG_LIMIT, APP_VERSION
} from '../common/Constants';

/** 迁移结果。`error` 非空时**禁止**调用方写回 `KEY-01`。 */
export interface MigrationResult {
  state: AppState;
  fromVersion: number;
  toVersion: number;
  migrated: boolean;
  error: string;
}

export class SchemaMigration {
  /** 目标版本 = 全局 `SCHEMA_VERSION`（唯一来源，不另立常量）。 */
  static readonly TARGET: number = SCHEMA_VERSION;

  /**
   * 迁进入口。
   *
   * `fromVersion` 由 `Serializer.decodeSchemaVersion()` 给出：解析失败即 0（视为首次启动）。
   * 返回的 `state` 在失败路径上**就是入参本身**（保留原数据），调用方不得据此覆盖磁盘。
   */
  static migrate(state: AppState, fromVersion: number): MigrationResult {
    const from: number = fromVersion > 0 ? Math.floor(fromVersion) : 0;

    if (from === SchemaMigration.TARGET) {
      const same: MigrationResult = {
        state: state,
        fromVersion: from,
        toVersion: SchemaMigration.TARGET,
        migrated: false,
        error: ''
      };
      return same;
    }

    if (from > SchemaMigration.TARGET) {
      const ahead: MigrationResult = {
        state: state,
        fromVersion: from,
        toVersion: SchemaMigration.TARGET,
        migrated: false,
        error: '存储数据版本 ' + from + ' 高于当前应用支持的 ' + SchemaMigration.TARGET +
          '，保留原数据且不做降级'
      };
      return ahead;
    }

    // from < TARGET：逐级链式。当前只有 0 → 1 一级，新增版本时在此加 step。
    let current: AppState = state;
    let version: number = from;
    try {
      while (version < SchemaMigration.TARGET) {
        current = SchemaMigration.step(current, version);
        version = version + 1;
      }
    } catch (err) {
      const failed: MigrationResult = {
        state: state, // 保留原数据
        fromVersion: from,
        toVersion: SchemaMigration.TARGET,
        migrated: false,
        error: '迁移失败（v' + from + ' → v' + SchemaMigration.TARGET + '）：' +
          (err instanceof Error ? err.message : '未知错误')
      };
      return failed;
    }

    const done: MigrationResult = {
      state: current,
      fromVersion: from,
      toVersion: SchemaMigration.TARGET,
      migrated: true,
      error: ''
    };
    return done;
  }

  /** 单级迁移分派：`fromVersion` → `fromVersion + 1`。 */
  private static step(state: AppState, fromVersion: number): AppState {
    if (fromVersion === 0) {
      return SchemaMigration.migrateV0ToV1(state);
    }
    // 未登记的版本级：保守起见原样返回（不猜结构），由上层比对 toVersion 发现缺口。
    return state;
  }

  /**
   * v0 → v1。
   *
   * v0 指阶段二/阶段三的**内存态**（当时 `flush()` 返回 `NO_CHANGE`，磁盘上不存在真实 v0 数据）。
   * 因此本级的职责只有两件事：
   *   ① **补齐缺失字段**：`logs` 四个数组、`returnSnapshot`、`rules`/`scenes`/`devices`、
   *      `settings`、`environment`、`currentMode`/`currentSceneId`、`schemaVersion`；
   *   ② **清空演示残留**：v0 的 `logs.ruleExecutions` 在设计上恒为 `[]`（护栏 A-6），
   *      若磁盘上出现非数组/非法值则重置为空数组；**不删除任何合法条目**。
   *
   * ★ 刻意不做的事：不按 id 过滤、不删规则、不删场景。迁移期删用户数据是不可逆伤害，
   *   而 v0 从未真正落盘，没有「演示数据」需要清。此判断已在交付报告中单列，等主理人裁决。
   */
  static migrateV0ToV1(state: AppState): AppState {
    const devices: Device[] = SchemaMigration.orEmpty<Device>(state.devices);
    const rules: AutomationRule[] = SchemaMigration.orEmpty<AutomationRule>(state.rules);
    const scenes: Scene[] = SchemaMigration.orEmpty<Scene>(state.scenes);
    const returnSnapshot: DeviceStateSnapshot[] =
      SchemaMigration.orEmpty<DeviceStateSnapshot>(state.returnSnapshot);
    const settings: AppSettings = SchemaMigration.orSettings(state.settings);
    const environment: EnvironmentData = SchemaMigration.orEnvironment(state.environment);
    const logs: LogBundle = SchemaMigration.normalizeLogs(state.logs);
    const mode: RunMode = SchemaMigration.normalizeMode(state.currentMode);
    const sceneId: string = SchemaMigration.orString(state.currentSceneId);

    const migrated: AppState = {
      schemaVersion: SchemaMigration.TARGET,
      devices: devices,
      rules: rules,
      scenes: scenes,
      settings: settings,
      environment: environment,
      logs: logs,
      returnSnapshot: returnSnapshot,
      currentMode: mode,
      currentSceneId: sceneId
    };
    return migrated;
  }

  /**
   * 数组缺失兜底。
   *
   * 形参故意写成 `T[] | undefined`：`AppState` 的字段在类型上非可选（TS 侧不该缺），
   * 但**磁盘上的旧数据可以缺**——那是运行期事实，不是类型事实。用这个「宽形参」
   * 才能既通过静态检查又真实兜住缺字段的数据。
   */
  private static orEmpty<T>(list: T[] | undefined): T[] {
    if (list === undefined || list === null) {
      return [];
    }
    return list;
  }

  /** 字符串缺失兜底。 */
  private static orString(value: string | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return value;
  }

  /** 设置缺失兜底。 */
  private static orSettings(value: AppSettings | undefined): AppSettings {
    if (value === undefined || value === null) {
      return SchemaMigration.fallbackSettings();
    }
    return value;
  }

  /** 环境缺失兜底。 */
  private static orEnvironment(value: EnvironmentData | undefined): EnvironmentData {
    if (value === undefined || value === null) {
      return SchemaMigration.fallbackEnvironment();
    }
    return value;
  }

  /** 四类日志数组缺失/非法时重置为空数组（不删合法条目）。 */
  private static normalizeLogs(logs: LogBundle | undefined): LogBundle {
    if (logs === undefined || logs === null) {
      const empty: LogBundle = {
        operations: [],
        ruleExecutions: [],
        environment: [],
        sceneSwitches: []
      };
      return empty;
    }
    const normalized: LogBundle = {
      operations: SchemaMigration.orEmpty<OperationLog>(logs.operations),
      ruleExecutions: SchemaMigration.orEmpty<RuleExecutionLog>(logs.ruleExecutions),
      environment: SchemaMigration.orEmpty<EnvironmentLog>(logs.environment),
      sceneSwitches: SchemaMigration.orEmpty<SceneSwitchLog>(logs.sceneSwitches)
    };
    return normalized;
  }

  /** `currentMode` 非法（缺字段 / 未知枚举）时退到 `MANUAL`（FR-01-07 的安全默认）。 */
  private static normalizeMode(mode: RunMode): RunMode {
    switch (mode) {
      case RunMode.STUDY:
      case RunMode.SLEEP:
      case RunMode.AWAY:
      case RunMode.RETURN:
      case RunMode.CUSTOM:
      case RunMode.MANUAL:
        return mode;
      default:
        return RunMode.MANUAL;
    }
  }

  /**
   * 缺失时的设置默认值。
   *
   * ★ 与 `mock/MockDataFactory.createDefaultSettings()` **数值一致**，但这里不能 import 它：
   *   `MockDataFactory` 依赖系统侧随机数能力，import 进来本类立即失去可测性（§4.5 注同理）。
   *   两处默认值若需调整，必须同改；T4-03 接线时建议由仓储层统一提供默认态，
   *   本方法退化为「最后兜底」。
   */
  private static fallbackSettings(): AppSettings {
    const settings: AppSettings = {
      automationEnabled: true,
      simulationEnabled: true,
      sampleIntervalMs: DEFAULT_SAMPLE_INTERVAL_MS,
      logLimit: DEFAULT_LOG_LIMIT,
      schemaVersion: SCHEMA_VERSION,
      appVersion: APP_VERSION
    };
    return settings;
  }

  /** 缺失时的环境默认值（PRD 4.4 基线：25℃ / 50%RH / 300Lux / 50AQI）。 */
  private static fallbackEnvironment(): EnvironmentData {
    const environment: EnvironmentData = {
      temperature: 25,
      humidity: 50,
      illuminance: 300,
      airQuality: 50,
      humanPresence: false,
      timestamp: 0,
      source: EnvSource.INIT
    };
    return environment;
  }
}
