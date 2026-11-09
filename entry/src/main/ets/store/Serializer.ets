/**
 * 智寓 · 分区序列化 / 反序列化（设计 8.6、任务列表-第四阶段 §1.1、§1.3、§4.3）
 *
 * 只做两件事：**对象 → 块字符串数组**、**块字符串数组 → 对象**。
 * 不读写 `AppState` 字段、不做 IO、不碰 `preferences`、不调服务层。
 *
 * ── 块格式（逐字，见 §1.1 裁决 3 / §1.3）─────────────────────────────────
 *   <base>.hdr      {"p":"DEVICES","n":2,"t":1794194731144,"v":1}
 *   <base>.c0000    {"p":"DEVICES","i":0,"t":1794194731144,"d":[<条目>,<条目>]}
 *   块头是**提交点**；块内不再重复 `n`（省体积、职责单一）。
 *
 * ── 四条不可违背的规则 ──────────────────────────────────────────────────
 *   ① **按条目边界装块**：块内永远是完整条目，绝不切断一条日志（§1.1 裁决 2）。
 *      每块总长度（含外层 `d` 包装、不含块头键）≤ `CHUNK_MAX_CHARS`。
 *   ② **单条守卫**：单条 `JSON.stringify` 后 > `ENTRY_GUARD_CHARS` → 该条不落盘
 *      （内存态保留）+ 计入 `droppedEntries` + 记诊断。理由：宁可丢 1 条超长日志，
 *      也不能让 `put` 抛 401 把**整个分区**写失败。
 *   ③ **三级一致性校验**（§1.1.3）：
 *      ① 有块无头 → 损坏；② `n` 大于实际块数（缺块）→ 损坏；
 *      ③ `n` 小于实际块数（孤儿块）→ **不算损坏**，按 `n` 截断 + INFO 诊断；
 *      ④ 块齐全但 JSON/字段类型不符 → 损坏；⑤ 守卫丢弃 → 不算损坏。
 *   ④ **块格式版本**：`v > 1` → 判损坏（不猜未来格式）；`v === 1` 或缺失（视为 1）→ 正常。
 *
 * ── 为什么不用一个泛型分发器 ─────────────────────────────────────────────
 * ArkTS 严格子集没有 `any`、`Object` 强转到具体类型也要走 `as unknown as` 这类禁用写法，
 * 泛型分发器最终只能退化成「两头都强转」。所以这里是「每分区一个类型化方法 + 一个
 * 结构性 `assemblePartition`（解码器作为参数注入）」：类型闭合、每个方法可独立单测。
 *
 * 本文件零系统 API 依赖（不 import 任何 Kit 模块），可在 Node 侧单测（判据 B1~B13）。
 *
 * 依据：design/任务列表-第四阶段.md 1.1、1.1.3、1.3、4.3。
 */
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import {
  DeviceParams, LightParams, AirConditionerParams, CurtainParams, DoorLockParams, FanParams, SocketParams
} from '../model/DeviceParams';
import { AutomationRule } from '../model/AutomationRule';
import { AutomationCondition } from '../model/AutomationCondition';
import { AutomationAction } from '../model/AutomationAction';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { EnvironmentData } from '../model/EnvironmentData';
import { AppSettings } from '../model/AppSettings';
import {
  OperationLog, RuleExecutionLog, EnvironmentLog, SceneSwitchLog, ActionExecutionDetail
} from '../model/Logs';
import {
  DeviceType, DeviceStatus, ACMode, SensorType, Operator, ConditionLogic, SceneType,
  LogActor, ResultCode, RuleExecStatus, EnvSource, DeviceCommand, RunMode
} from '../model/Enums';
import { StoragePartition, ChunkHeader } from './StorageKeys';
import { StorageDiagnostics, DiagnosticLevel } from './StorageDiagnostics';
import {
  CHUNK_MAX_CHARS, ENTRY_GUARD_CHARS, CHUNK_INDEX_MAX, CHUNK_FORMAT_VERSION
} from '../common/Constants';
import { TimeUtil } from '../common/TimeUtil';

/** 运行时元信息结构版本（缺失视为 1）。 */
const RUNTIME_FORMAT_VERSION: number = 1;

/** 块尾部 `]}` 的固定长度（装块预算里要减掉）。 */
const CHUNK_TAIL_LEN: number = 2;

// —— 枚举白名单（不用 Object.values：ArkTS 下行为不稳；逐个字面量列出，编译期即可核对）——
const DEVICE_TYPE_VALUES: string[] = [
  DeviceType.LIGHT, DeviceType.AIR_CONDITIONER, DeviceType.CURTAIN,
  DeviceType.DOOR_LOCK, DeviceType.FAN, DeviceType.SOCKET
];
const DEVICE_STATUS_VALUES: string[] = [
  DeviceStatus.RUNNING, DeviceStatus.IDLE, DeviceStatus.FAULT, DeviceStatus.OFFLINE
];
const AC_MODE_VALUES: string[] = [
  ACMode.COOL, ACMode.HEAT, ACMode.FAN, ACMode.DRY, ACMode.AUTO
];
const SENSOR_TYPE_VALUES: string[] = [
  SensorType.TEMPERATURE, SensorType.HUMIDITY, SensorType.ILLUMINANCE,
  SensorType.AIR_QUALITY, SensorType.HUMAN_PRESENCE
];
const OPERATOR_VALUES: string[] = [
  Operator.GT, Operator.LT, Operator.IS_TRUE, Operator.IS_FALSE
];
const CONDITION_LOGIC_VALUES: string[] = [ConditionLogic.AND];
const SCENE_TYPE_VALUES: string[] = [
  SceneType.STUDY, SceneType.SLEEP, SceneType.AWAY, SceneType.RETURN, SceneType.CUSTOM
];
const LOG_ACTOR_VALUES: string[] = [
  LogActor.USER, LogActor.RULE, LogActor.SCENE, LogActor.SYSTEM
];
const RESULT_CODE_VALUES: string[] = [
  ResultCode.OK, ResultCode.NO_CHANGE, ResultCode.NOT_FOUND, ResultCode.INVALID_PARAM,
  ResultCode.DEVICE_OFFLINE, ResultCode.CONFLICT_SKIPPED, ResultCode.STORAGE_ERROR,
  ResultCode.UNKNOWN
];
const RULE_EXEC_STATUS_VALUES: string[] = [
  RuleExecStatus.SUCCESS, RuleExecStatus.PARTIAL, RuleExecStatus.FAILED,
  RuleExecStatus.SKIPPED_DEDUP, RuleExecStatus.SKIPPED_CONFLICT, RuleExecStatus.SKIPPED_DISABLED
];
const ENV_SOURCE_VALUES: string[] = [EnvSource.MANUAL, EnvSource.SIMULATED, EnvSource.INIT];
const DEVICE_COMMAND_VALUES: string[] = [
  DeviceCommand.POWER_ON, DeviceCommand.POWER_OFF, DeviceCommand.SET_BRIGHTNESS,
  DeviceCommand.SET_TEMPERATURE, DeviceCommand.SET_MODE, DeviceCommand.SET_OPEN_PERCENT,
  DeviceCommand.LOCK, DeviceCommand.UNLOCK, DeviceCommand.SET_FAN_SPEED,
  DeviceCommand.SET_POWER, DeviceCommand.SOCKET_ON, DeviceCommand.SOCKET_OFF
];
const RUN_MODE_VALUES: string[] = [
  RunMode.STUDY, RunMode.SLEEP, RunMode.AWAY, RunMode.RETURN, RunMode.CUSTOM, RunMode.MANUAL
];

/** 编码结果（`WriteQueue` 的 `PartitionEncoder` 适配器只取 `chunks`）。 */
export interface EncodeResult {
  header: ChunkHeader; // 序列化成 <base>.hdr
  chunks: string[]; // 序列化成 <base>.c0000..c(n-1)，顺序即 i
  totalEntries: number; // 候选条目总数（含被守卫丢弃的）
  droppedEntries: number; // 触发 ENTRY_GUARD_CHARS 被丢弃的条目数
  error: string; // 空串表示无错
}

/** 解码结果。`dropped` = 被丢弃的条目数（守卫丢弃 + 校验失败丢弃）。 */
export interface DecodeResult<T> {
  ok: boolean;
  data?: T;
  error: string;
  dropped: number;
}

/** 运行时元信息（`KEY-11`）。 */
export interface RuntimeMeta {
  currentSceneId: string;
  currentMode: RunMode;
  firstLaunchAt: number;
  lastLaunchAt: number;
  bootCount: number;
}

/** `KEY-11` 的落盘结构（带结构版本 `v`，便于将来加字段）。 */
interface RuntimeMetaRaw {
  v: number;
  currentSceneId: string;
  currentMode: RunMode;
  firstLaunchAt: number;
  lastLaunchAt: number;
  bootCount: number;
}

/** `SCENES` 分区的载荷：场景 + 切换日志（设计 §8.6.1：切换日志随场景分区）。 */
export interface ScenePartition {
  scenes: Scene[];
  sceneSwitches: SceneSwitchLog[];
}

/** 单分区解码器（供 `assemblePartition` 注入，避免泛型分发器强转）。 */
export type PartitionDecoder<T> = (chunkRaws: string[]) => DecodeResult<T>;

/** `collect()` 的中间结果：把脏活（解析/分区校验/守卫）集中一处。 */
interface Collected {
  ok: boolean;
  error: string;
  entries: Record<string, Object>[];
  dropped: number;
}

export class Serializer {
  // ——————————————————————————————————————————————————————————
  // 编码：AppState → 块字符串数组
  // ——————————————————————————————————————————————————————————

  /**
   * 按分区编码。
   *
   * `META` **不经本方法**（§4.3 表：`KEY-01` 是标量字符串、`KEY-11` 是 JSON），
   * 调用它会得到 `chunks: []` 与 `error` 非空，提醒调用方走 `writeMeta()` 分支。
   */
  static encodePartition(partition: StoragePartition, state: AppState): EncodeResult {
    const now: number = TimeUtil.now();
    if (partition === StoragePartition.META) {
      const header: ChunkHeader = {
        p: partition, n: 0, t: now, v: CHUNK_FORMAT_VERSION
      };
      const rejected: EncodeResult = {
        header: header,
        chunks: [],
        totalEntries: 0,
        droppedEntries: 0,
        error: 'META 走标量键分支（KEY-01 / KEY-11），不经 encodePartition'
      };
      return rejected;
    }

    const items: string[] = Serializer.itemsOf(partition, state);
    const total: number = items.length;
    let dropped: number = 0;
    let index: number = 0;
    let entries: string[] = [];
    let bodyLen: number = 0;
    const chunks: string[] = [];

    for (let k = 0; k < items.length; k++) {
      const item: string = items[k];
      if (item.length > ENTRY_GUARD_CHARS) {
        // ② 单条守卫：不落盘，其余条目完整（§1.1 裁决 4）
        dropped = dropped + 1;
        StorageDiagnostics.getInstance().record(
          DiagnosticLevel.WARN, 'ENTRY_DROPPED',
          partition + ' 单条 ' + item.length + ' 字符 > ' + ENTRY_GUARD_CHARS + '，本条不落盘'
        );
        continue;
      }
      const sepLen: number = entries.length === 0 ? 0 : 1;
      const prefixLen: number = Serializer.chunkPrefix(partition, index, now).length;
      const need: number = prefixLen + bodyLen + sepLen + item.length + CHUNK_TAIL_LEN;
      if (entries.length > 0 && need > CHUNK_MAX_CHARS) {
        chunks.push(Serializer.chunkPrefix(partition, index, now) + entries.join(',') + ']}');
        index = index + 1;
        if (index > CHUNK_INDEX_MAX) {
          const overflow: EncodeResult = {
            header: { p: partition, n: chunks.length, t: now, v: CHUNK_FORMAT_VERSION },
            chunks: chunks,
            totalEntries: total,
            droppedEntries: dropped,
            error: '块数超上限 ' + (CHUNK_INDEX_MAX + 1) + '：' + partition
          };
          return overflow;
        }
        entries = [];
        bodyLen = 0;
      }
      const sep: number = entries.length === 0 ? 0 : 1;
      entries.push(item);
      bodyLen = bodyLen + sep + item.length;
    }
    if (entries.length > 0) {
      chunks.push(Serializer.chunkPrefix(partition, index, now) + entries.join(',') + ']}');
    }

    const header: ChunkHeader = {
      p: partition,
      n: chunks.length,
      t: now,
      v: CHUNK_FORMAT_VERSION
    };
    const result: EncodeResult = {
      header: header,
      chunks: chunks,
      totalEntries: total,
      droppedEntries: dropped,
      error: ''
    };
    return result;
  }

  /** 块头序列化（`WriteQueue.writeHeader` 用它落 `<base>.hdr`）。 */
  static encodeHeader(header: ChunkHeader): string {
    const raw: string = JSON.stringify(header);
    return raw;
  }

  /** 块头反序列化：校验字段类型、分区一致性、块格式版本（`v > 1` 判损坏）。 */
  static decodeHeader(raw: string): DecodeResult<ChunkHeader> {
    if (!raw) {
      return Serializer.fail<ChunkHeader>('HEADER_MISSING: 块头为空', 0);
    }
    const obj: Record<string, Object> | undefined = Serializer.asObject(raw);
    if (obj === undefined) {
      return Serializer.fail<ChunkHeader>('HEADER_INVALID: 块头不是合法 JSON 对象', 0);
    }
    const pStr: string | undefined = Serializer.readString(obj, 'p');
    const n: number | undefined = Serializer.readNumber(obj, 'n');
    const t: number | undefined = Serializer.readNumber(obj, 't');
    if (pStr === undefined || !Serializer.inPartitionList(pStr) || n === undefined ||
      t === undefined || n < 0 || Math.floor(n) !== n) {
      return Serializer.fail<ChunkHeader>('HEADER_INVALID: 块头字段缺失或类型不符', 0);
    }
    const vRaw: number | undefined = Serializer.readNumber(obj, 'v');
    const v: number = vRaw === undefined ? CHUNK_FORMAT_VERSION : vRaw;
    if (v > CHUNK_FORMAT_VERSION) {
      // ④ 不猜未来格式（§1.3）
      return Serializer.fail<ChunkHeader>(
        'HEADER_VERSION: 块格式版本 v=' + v + ' 高于当前支持的 ' + CHUNK_FORMAT_VERSION, 0);
    }
    const header: ChunkHeader = {
      p: pStr as StoragePartition,
      n: n,
      t: t,
      v: v
    };
    return Serializer.ok<ChunkHeader>(header, 0);
  }

  /** `KEY-11` 运行时元信息序列化。 */
  static encodeRuntime(meta: RuntimeMeta): string {
    const raw: RuntimeMetaRaw = {
      v: RUNTIME_FORMAT_VERSION,
      currentSceneId: meta.currentSceneId,
      currentMode: meta.currentMode,
      firstLaunchAt: meta.firstLaunchAt,
      lastLaunchAt: meta.lastLaunchAt,
      bootCount: meta.bootCount
    };
    return JSON.stringify(raw);
  }

  /** `KEY-11` 反序列化；字段缺失/类型不符 → `ok:false`（调用方退 `defaultRuntime`）。 */
  static decodeRuntime(raw: string): DecodeResult<RuntimeMeta> {
    if (!raw) {
      return Serializer.fail<RuntimeMeta>('RUNTIME_EMPTY: 运行时元信息缺失', 0);
    }
    const obj: Record<string, Object> | undefined = Serializer.asObject(raw);
    if (obj === undefined) {
      return Serializer.fail<RuntimeMeta>('RUNTIME_INVALID: 运行时元信息不是合法 JSON 对象', 0);
    }
    const sceneId: string | undefined = Serializer.readString(obj, 'currentSceneId');
    const modeStr: string | undefined = Serializer.readString(obj, 'currentMode');
    const first: number | undefined = Serializer.readNumber(obj, 'firstLaunchAt');
    const last: number | undefined = Serializer.readNumber(obj, 'lastLaunchAt');
    const boot: number | undefined = Serializer.readNumber(obj, 'bootCount');
    if (sceneId === undefined || modeStr === undefined || !Serializer.inList(modeStr, RUN_MODE_VALUES) ||
      first === undefined || last === undefined || boot === undefined) {
      return Serializer.fail<RuntimeMeta>('RUNTIME_INVALID: 运行时元信息字段缺失或类型不符', 0);
    }
    const meta: RuntimeMeta = {
      currentSceneId: sceneId,
      currentMode: modeStr as RunMode,
      firstLaunchAt: first,
      lastLaunchAt: last,
      bootCount: boot
    };
    return Serializer.ok<RuntimeMeta>(meta, 0);
  }

  /** 首次启动的运行时元信息。 */
  static defaultRuntime(now: number): RuntimeMeta {
    const meta: RuntimeMeta = {
      currentSceneId: '',
      currentMode: RunMode.MANUAL,
      firstLaunchAt: now,
      lastLaunchAt: now,
      bootCount: 1
    };
    return meta;
  }

  /**
   * `KEY-01` 版本号解析：**纯十进制数字**才算数，其余一律 0（→ 视为首次启动）。
   *
   * 为什么不用 `parseInt`：`parseInt('1.5')` 得 1、`parseInt('12abc')` 得 12，
   * 会把脏数据静默当成合法版本号，进而跳过迁移。这里逐字符校验 + 限长，
   * 任何「看起来像但不是版本号」的输入都返回 0。
   */
  static decodeSchemaVersion(raw: string): number {
    if (!raw) {
      return 0;
    }
    if (raw.length > 6) {
      return 0; // '9999999999999' 这类明显不是版本号
    }
    let value: number = 0;
    for (let i = 0; i < raw.length; i++) {
      const code: number = raw.charCodeAt(i);
      if (code < 48 || code > 57) {
        return 0; // '-' '.' 'a' 等一律拒绝
      }
      value = value * 10 + (code - 48);
    }
    return value;
  }

  // ——————————————————————————————————————————————————————————
  // 读路径编排：结构校验 → 截断孤儿块 → 交给分区解码器
  // ——————————————————————————————————————————————————————————

  /**
   * 一个分区的读路径编排（**不含 IO**）。
   *
   * 步骤：① 解块头（含版本校验）→ ② 逐块解析并校验 `p` / `i` 唯一性 →
   * ③ 按 `n` 校验缺块（② 损坏）/ 多余块（③ 不判损坏，截断 + INFO 诊断）→
   * ④ 按 `i` 升序把块原文交给 `decode`。
   *
   * 解码器以参数注入而不是内部 `switch` 分发：泛型分发在 ArkTS 下只能靠禁用写法强转
   * （见文件头说明）。调用方写 `assemblePartition(StoragePartition.DEVICES, hdr, raws, Serializer.decodeDevices)`。
   */
  static assemblePartition<T>(partition: StoragePartition, headerRaw: string,
    chunkRaws: string[], decode: PartitionDecoder<T>): DecodeResult<T> {
    if (!headerRaw && chunkRaws.length === 0) {
      return Serializer.fail<T>('EMPTY: 分区既无块头也无块', 0);
    }
    if (!headerRaw) {
      // ① 有块无头 → 损坏（§1.1.3 ①）
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.WARN, 'HEADER_MISSING', partition + ' 有 ' + chunkRaws.length + ' 块但块头缺失');
      return Serializer.fail<T>('HEADER_MISSING: 有块但块头缺失', 0);
    }

    const headerResult: DecodeResult<ChunkHeader> = Serializer.decodeHeader(headerRaw);
    if (!headerResult.ok || headerResult.data === undefined) {
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.ERROR, 'HEADER_INVALID', partition + ' ' + headerResult.error);
      return Serializer.fail<T>(headerResult.error, 0);
    }
    const header: ChunkHeader = headerResult.data;
    if (header.p !== partition) {
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.ERROR, 'HEADER_PARTITION', '块头声明 ' + header.p + '，期望 ' + partition);
      return Serializer.fail<T>('HEADER_PARTITION: 块头分区不匹配', 0);
    }

    const byIndex: Map<number, string> = new Map<number, string>();
    for (let k = 0; k < chunkRaws.length; k++) {
      const raw: string = chunkRaws[k];
      const obj: Record<string, Object> | undefined = Serializer.asObject(raw);
      if (obj === undefined) {
        StorageDiagnostics.getInstance().record(
          DiagnosticLevel.ERROR, 'CHUNK_INVALID', partition + ' 第 ' + k + ' 个块不是合法 JSON 对象');
        return Serializer.fail<T>('CHUNK_INVALID: 第 ' + k + ' 个块 JSON 非法', 0);
      }
      const pStr: string | undefined = Serializer.readString(obj, 'p');
      const i: number | undefined = Serializer.readNumber(obj, 'i');
      if (pStr === undefined || pStr !== partition || i === undefined || i < 0 ||
        Math.floor(i) !== i) {
        StorageDiagnostics.getInstance().record(
          DiagnosticLevel.ERROR, 'CHUNK_INVALID',
          partition + ' 第 ' + k + ' 个块的 p/i 字段非法');
        return Serializer.fail<T>('CHUNK_INVALID: 第 ' + k + ' 个块 p/i 字段非法', 0);
      }
      if (byIndex.has(i)) {
        StorageDiagnostics.getInstance().record(
          DiagnosticLevel.ERROR, 'CHUNK_DUPLICATE', partition + ' 块索引 ' + i + ' 重复');
        return Serializer.fail<T>('CHUNK_DUPLICATE: 块索引 ' + i + ' 重复', 0);
      }
      byIndex.set(i, raw);
    }

    const missing: number[] = [];
    for (let k = 0; k < header.n; k++) {
      if (!byIndex.has(k)) {
        missing.push(k);
      }
    }
    if (missing.length > 0) {
      // ② 缺块 = 数据残缺 = 损坏（§1.1.3 ②）
      const list: string = missing.join(',');
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.ERROR, 'CHUNK_MISSING',
        partition + ' 缺少块索引 [' + list + ']，块头 n=' + header.n);
      return Serializer.fail<T>(
        'CHUNK_MISSING: 缺少块索引 [' + list + ']（块头 n=' + header.n + '）', 0);
    }

    let extra: number = 0;
    byIndex.forEach((value: string, key: number): void => {
      if (key >= header.n) {
        extra = extra + 1;
      }
    });
    if (extra > 0) {
      // ③ 孤儿块：不判损坏，按 n 截断 + INFO 诊断 + 下次写入清理（§1.1.1 步 3）
      StorageDiagnostics.getInstance().record(
        DiagnosticLevel.INFO, 'EXTRA_CHUNK',
        partition + ' 发现 ' + extra + ' 个索引 ≥ n=' + header.n + ' 的孤儿块，按 n 截断加载');
    }

    const ordered: string[] = [];
    for (let k = 0; k < header.n; k++) {
      const raw: string | undefined = byIndex.get(k);
      if (raw !== undefined) {
        ordered.push(raw);
      }
    }
    return decode(ordered);
  }

  // ——————————————————————————————————————————————————————————
  // 分区解码器（每个类型闭合、可独立单测）
  // ——————————————————————————————————————————————————————————

  static decodeDevices(raws: string[]): DecodeResult<Device[]> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.DEVICES);
    if (!collected.ok) {
      return Serializer.fail<Device[]>(collected.error, collected.dropped);
    }
    const data: Device[] = [];
    for (let i = 0; i < collected.entries.length; i++) {
      const device: Device | undefined = Serializer.parseDevice(collected.entries[i]);
      if (device === undefined) {
        return Serializer.fail<Device[]>(
          'INVALID_ENTRY: DEVICES 第 ' + i + ' 条字段类型不符或缺字段', collected.dropped);
      }
      data.push(device);
    }
    return Serializer.ok<Device[]>(data, collected.dropped);
  }

  static decodeRules(raws: string[]): DecodeResult<AutomationRule[]> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.RULES);
    if (!collected.ok) {
      return Serializer.fail<AutomationRule[]>(collected.error, collected.dropped);
    }
    const data: AutomationRule[] = [];
    for (let i = 0; i < collected.entries.length; i++) {
      const rule: AutomationRule | undefined = Serializer.parseRule(collected.entries[i]);
      if (rule === undefined) {
        return Serializer.fail<AutomationRule[]>(
          'INVALID_ENTRY: RULES 第 ' + i + ' 条字段类型不符或缺字段', collected.dropped);
      }
      data.push(rule);
    }
    return Serializer.ok<AutomationRule[]>(data, collected.dropped);
  }

  static decodeScenes(raws: string[]): DecodeResult<ScenePartition> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.SCENES);
    if (!collected.ok) {
      return Serializer.fail<ScenePartition>(collected.error, collected.dropped);
    }
    const scenes: Scene[] = [];
    const switches: SceneSwitchLog[] = [];
    for (let i = 0; i < collected.entries.length; i++) {
      const entry: Record<string, Object> = collected.entries[i];
      const kind: string | undefined = Serializer.readString(entry, 'k');
      const value: Record<string, Object> | undefined = Serializer.readObject(entry, 'v');
      if (kind === undefined || value === undefined) {
        return Serializer.fail<ScenePartition>(
          'INVALID_ENTRY: SCENES 第 ' + i + ' 条缺少 k/v 字段', collected.dropped);
      }
      if (kind === 'S') {
        const scene: Scene | undefined = Serializer.parseScene(value);
        if (scene === undefined) {
          return Serializer.fail<ScenePartition>(
            'INVALID_ENTRY: SCENES 第 ' + i + ' 条场景字段不符', collected.dropped);
        }
        scenes.push(scene);
      } else if (kind === 'L') {
        const log: SceneSwitchLog | undefined = Serializer.parseSceneSwitchLog(value);
        if (log === undefined) {
          return Serializer.fail<ScenePartition>(
            'INVALID_ENTRY: SCENES 第 ' + i + ' 条切换日志字段不符', collected.dropped);
        }
        switches.push(log);
      } else {
        return Serializer.fail<ScenePartition>(
          'INVALID_ENTRY: SCENES 第 ' + i + ' 条 k=' + kind + ' 未知', collected.dropped);
      }
    }
    const data: ScenePartition = { scenes: scenes, sceneSwitches: switches };
    return Serializer.ok<ScenePartition>(data, collected.dropped);
  }

  static decodeSettings(raws: string[]): DecodeResult<AppSettings> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.SETTINGS);
    if (!collected.ok) {
      return Serializer.fail<AppSettings>(collected.error, collected.dropped);
    }
    // 单对象分区：d 为空 → 损坏（§4.3 说明）
    if (collected.entries.length !== 1) {
      return Serializer.fail<AppSettings>(
        'INVALID_ENTRY: SETTINGS 期望 1 条，实际 ' + collected.entries.length + ' 条',
        collected.dropped);
    }
    const settings: AppSettings | undefined = Serializer.parseSettings(collected.entries[0]);
    if (settings === undefined) {
      return Serializer.fail<AppSettings>(
        'INVALID_ENTRY: SETTINGS 字段类型不符或缺字段', collected.dropped);
    }
    return Serializer.ok<AppSettings>(settings, collected.dropped);
  }

  static decodeEnvironment(raws: string[]): DecodeResult<EnvironmentData> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.ENVIRONMENT);
    if (!collected.ok) {
      return Serializer.fail<EnvironmentData>(collected.error, collected.dropped);
    }
    if (collected.entries.length !== 1) {
      return Serializer.fail<EnvironmentData>(
        'INVALID_ENTRY: ENVIRONMENT 期望 1 条，实际 ' + collected.entries.length + ' 条',
        collected.dropped);
    }
    const environment: EnvironmentData | undefined =
      Serializer.parseEnvironment(collected.entries[0]);
    if (environment === undefined) {
      return Serializer.fail<EnvironmentData>(
        'INVALID_ENTRY: ENVIRONMENT 字段类型不符或缺字段', collected.dropped);
    }
    return Serializer.ok<EnvironmentData>(environment, collected.dropped);
  }

  static decodeOperationLogs(raws: string[]): DecodeResult<OperationLog[]> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.OPERATION_LOGS);
    if (!collected.ok) {
      return Serializer.fail<OperationLog[]>(collected.error, collected.dropped);
    }
    const data: OperationLog[] = [];
    for (let i = 0; i < collected.entries.length; i++) {
      const log: OperationLog | undefined = Serializer.parseOperationLog(collected.entries[i]);
      if (log === undefined) {
        return Serializer.fail<OperationLog[]>(
          'INVALID_ENTRY: OPERATION_LOGS 第 ' + i + ' 条字段不符', collected.dropped);
      }
      data.push(log);
    }
    return Serializer.ok<OperationLog[]>(data, collected.dropped);
  }

  static decodeRuleExecLogs(raws: string[]): DecodeResult<RuleExecutionLog[]> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.RULE_EXEC_LOGS);
    if (!collected.ok) {
      return Serializer.fail<RuleExecutionLog[]>(collected.error, collected.dropped);
    }
    const data: RuleExecutionLog[] = [];
    for (let i = 0; i < collected.entries.length; i++) {
      const log: RuleExecutionLog | undefined = Serializer.parseRuleExecLog(collected.entries[i]);
      if (log === undefined) {
        return Serializer.fail<RuleExecutionLog[]>(
          'INVALID_ENTRY: RULE_EXEC_LOGS 第 ' + i + ' 条字段不符', collected.dropped);
      }
      data.push(log);
    }
    return Serializer.ok<RuleExecutionLog[]>(data, collected.dropped);
  }

  static decodeEnvironmentLogs(raws: string[]): DecodeResult<EnvironmentLog[]> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.ENVIRONMENT_LOGS);
    if (!collected.ok) {
      return Serializer.fail<EnvironmentLog[]>(collected.error, collected.dropped);
    }
    const data: EnvironmentLog[] = [];
    for (let i = 0; i < collected.entries.length; i++) {
      const log: EnvironmentLog | undefined = Serializer.parseEnvironmentLog(collected.entries[i]);
      if (log === undefined) {
        return Serializer.fail<EnvironmentLog[]>(
          'INVALID_ENTRY: ENVIRONMENT_LOGS 第 ' + i + ' 条字段不符', collected.dropped);
      }
      data.push(log);
    }
    return Serializer.ok<EnvironmentLog[]>(data, collected.dropped);
  }

  static decodeReturnSnapshot(raws: string[]): DecodeResult<DeviceStateSnapshot[]> {
    const collected: Collected = Serializer.collect(raws, StoragePartition.RETURN_SNAPSHOT);
    if (!collected.ok) {
      return Serializer.fail<DeviceStateSnapshot[]>(collected.error, collected.dropped);
    }
    const data: DeviceStateSnapshot[] = [];
    for (let i = 0; i < collected.entries.length; i++) {
      const snapshot: DeviceStateSnapshot | undefined =
        Serializer.parseSnapshot(collected.entries[i]);
      if (snapshot === undefined) {
        return Serializer.fail<DeviceStateSnapshot[]>(
          'INVALID_ENTRY: RETURN_SNAPSHOT 第 ' + i + ' 条字段不符', collected.dropped);
      }
      data.push(snapshot);
    }
    return Serializer.ok<DeviceStateSnapshot[]>(data, collected.dropped);
  }

  // ——————————————————————————————————————————————————————————
  // 编码内部：分区 → 条目 JSON 字符串数组
  // ——————————————————————————————————————————————————————————

  /**
   * 取该分区的候选条目（已是 `JSON.stringify` 后的字符串，便于逐条量长度）。
   *
   * `SCENES` 需要承载两组数据，条目用 `{"k":"S","v":<scene>}` / `{"k":"L","v":<log>}` 打标签：
   * 不加标签就无法在解码时区分「场景」与「切换日志」，而两者结构完全不同。
   */
  private static itemsOf(partition: StoragePartition, state: AppState): string[] {
    const items: string[] = [];
    switch (partition) {
      case StoragePartition.DEVICES:
        for (let i = 0; i < state.devices.length; i++) {
          items.push(JSON.stringify(state.devices[i]));
        }
        break;
      case StoragePartition.RULES:
        for (let i = 0; i < state.rules.length; i++) {
          items.push(JSON.stringify(state.rules[i]));
        }
        break;
      case StoragePartition.SCENES:
        for (let i = 0; i < state.scenes.length; i++) {
          items.push('{"k":"S","v":' + JSON.stringify(state.scenes[i]) + '}');
        }
        for (let i = 0; i < state.logs.sceneSwitches.length; i++) {
          items.push('{"k":"L","v":' + JSON.stringify(state.logs.sceneSwitches[i]) + '}');
        }
        break;
      case StoragePartition.SETTINGS:
        items.push(JSON.stringify(state.settings));
        break;
      case StoragePartition.ENVIRONMENT:
        items.push(JSON.stringify(state.environment));
        break;
      case StoragePartition.OPERATION_LOGS:
        for (let i = 0; i < state.logs.operations.length; i++) {
          items.push(JSON.stringify(state.logs.operations[i]));
        }
        break;
      case StoragePartition.RULE_EXEC_LOGS:
        for (let i = 0; i < state.logs.ruleExecutions.length; i++) {
          items.push(JSON.stringify(state.logs.ruleExecutions[i]));
        }
        break;
      case StoragePartition.ENVIRONMENT_LOGS:
        for (let i = 0; i < state.logs.environment.length; i++) {
          items.push(JSON.stringify(state.logs.environment[i]));
        }
        break;
      case StoragePartition.RETURN_SNAPSHOT:
        for (let i = 0; i < state.returnSnapshot.length; i++) {
          items.push(JSON.stringify(state.returnSnapshot[i]));
        }
        break;
      default:
        break; // META 在上层已拦截
    }
    return items;
  }

  /** 块前缀 `{"p":"<分区>","i":<序号>,"t":<时间>,"d":[`（长度随序号位数变化，装块时必须逐块重算）。 */
  private static chunkPrefix(partition: StoragePartition, index: number, timestamp: number): string {
    return '{"p":"' + partition + '","i":' + index + ',"t":' + timestamp + ',"d":[';
  }

  // ——————————————————————————————————————————————————————————
  // 解码内部：块 → 条目对象数组（含守卫逐条过滤）
  // ——————————————————————————————————————————————————————————

  /**
   * 把块原文拆成「已通过外层结构校验的条目对象数组」。
   *
   * 这里集中三件脏活：① 块 JSON 解析；② `d` 是数组；③ **单条守卫复检**
   * （`JSON.stringify(entry).length > ENTRY_GUARD_CHARS` → 丢弃并计数）。
   * 守卫在解码侧再查一遍是刻意的：块可能是旧版本或手工写入的，不能假设写入方守规矩。
   */
  private static collect(raws: string[], partition: StoragePartition): Collected {
    const entries: Record<string, Object>[] = [];
    let dropped: number = 0;
    for (let k = 0; k < raws.length; k++) {
      const obj: Record<string, Object> | undefined = Serializer.asObject(raws[k]);
      if (obj === undefined) {
        const bad: Collected = {
          ok: false, error: 'CHUNK_INVALID: ' + partition + ' 第 ' + k + ' 个块 JSON 非法',
          entries: [], dropped: dropped
        };
        return bad;
      }
      const pStr: string | undefined = Serializer.readString(obj, 'p');
      if (pStr !== undefined && pStr !== partition) {
        const mismatch: Collected = {
          ok: false, error: 'CHUNK_PARTITION: 第 ' + k + ' 个块声明 ' + pStr + '，期望 ' + partition,
          entries: [], dropped: dropped
        };
        return mismatch;
      }
      const list: Object[] | undefined = Serializer.readArray(obj, 'd');
      if (list === undefined) {
        const noArray: Collected = {
          ok: false, error: 'CHUNK_INVALID: ' + partition + ' 第 ' + k + ' 个块缺少 d 数组',
          entries: [], dropped: dropped
        };
        return noArray;
      }
      for (let i = 0; i < list.length; i++) {
        const item: Object | null = list[i];
        if (typeof item !== 'object' || item === null) {
          const notObject: Collected = {
            ok: false,
            error: 'INVALID_ENTRY: ' + partition + ' 第 ' + k + ' 块第 ' + i + ' 条不是对象',
            entries: [], dropped: dropped
          };
          return notObject;
        }
        const entry: Record<string, Object> = item as Record<string, Object>;
        if (JSON.stringify(entry).length > ENTRY_GUARD_CHARS) {
          // ⑤ 守卫丢弃：不算损坏（§1.1.3 ⑤），但必须计数
          dropped = dropped + 1;
          StorageDiagnostics.getInstance().record(
            DiagnosticLevel.INFO, 'ENTRY_SKIPPED',
            partition + ' 加载时跳过 1 条超长条目（>' + ENTRY_GUARD_CHARS + ' 字符）');
          continue;
        }
        entries.push(entry);
      }
    }
    const ok: Collected = { ok: true, error: '', entries: entries, dropped: dropped };
    return ok;
  }

  // ——————————————————————————————————————————————————————————
  // 字段级解析（每个返回 undefined 表示该条不合格）
  // ——————————————————————————————————————————————————————————

  private static parseDevice(o: Record<string, Object>): Device | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const name: string | undefined = Serializer.readNonEmptyString(o, 'name');
    const typeStr: string | undefined = Serializer.readString(o, 'type');
    const powerOn: boolean | undefined = Serializer.readBoolean(o, 'powerOn');
    const online: boolean | undefined = Serializer.readBoolean(o, 'online');
    const locked: boolean | undefined = Serializer.readBoolean(o, 'locked');
    const statusStr: string | undefined = Serializer.readString(o, 'status');
    const createdAt: number | undefined = Serializer.readNumber(o, 'createdAt');
    const lastUpdated: number | undefined = Serializer.readNumber(o, 'lastUpdated');
    const paramsObj: Record<string, Object> | undefined = Serializer.readObject(o, 'params');
    if (id === undefined || name === undefined || typeStr === undefined ||
      !Serializer.inList(typeStr, DEVICE_TYPE_VALUES) || powerOn === undefined ||
      online === undefined || locked === undefined || statusStr === undefined ||
      !Serializer.inList(statusStr, DEVICE_STATUS_VALUES) || createdAt === undefined ||
      lastUpdated === undefined || paramsObj === undefined) {
      return undefined;
    }
    const type: DeviceType = typeStr as DeviceType;
    const params: DeviceParams | undefined = Serializer.parseParams(paramsObj);
    if (params === undefined) {
      return undefined;
    }
    if (params.kind !== type) {
      // SC-01：params.kind 必须与 device.type 一致（DeviceService.validate 同口径）
      return undefined;
    }
    const device: Device = {
      id: id,
      name: name,
      type: type,
      powerOn: powerOn,
      params: params,
      online: online,
      status: statusStr as DeviceStatus,
      locked: locked,
      createdAt: createdAt,
      lastUpdated: lastUpdated
    };
    return device;
  }

  /** 判别联合收窄：先读 `kind` 做 switch，再访问各自字段（AT-04 红线）。 */
  private static parseParams(o: Record<string, Object>): DeviceParams | undefined {
    const kindStr: string | undefined = Serializer.readString(o, 'kind');
    if (kindStr === undefined || !Serializer.inList(kindStr, DEVICE_TYPE_VALUES)) {
      return undefined;
    }
    const kind: DeviceType = kindStr as DeviceType;
    switch (kind) {
      case DeviceType.LIGHT: {
        const brightness: number | undefined = Serializer.readNumber(o, 'brightness');
        if (brightness === undefined) {
          return undefined;
        }
        const params: LightParams = { kind: DeviceType.LIGHT, brightness: brightness };
        return params;
      }
      case DeviceType.AIR_CONDITIONER: {
        const temperature: number | undefined = Serializer.readNumber(o, 'temperature');
        const modeStr: string | undefined = Serializer.readString(o, 'mode');
        if (temperature === undefined || modeStr === undefined ||
          !Serializer.inList(modeStr, AC_MODE_VALUES)) {
          return undefined;
        }
        const params: AirConditionerParams = {
          kind: DeviceType.AIR_CONDITIONER, temperature: temperature, mode: modeStr as ACMode
        };
        return params;
      }
      case DeviceType.CURTAIN: {
        const openPercent: number | undefined = Serializer.readNumber(o, 'openPercent');
        if (openPercent === undefined) {
          return undefined;
        }
        const params: CurtainParams = { kind: DeviceType.CURTAIN, openPercent: openPercent };
        return params;
      }
      case DeviceType.DOOR_LOCK: {
        const locked: boolean | undefined = Serializer.readBoolean(o, 'locked');
        if (locked === undefined) {
          return undefined;
        }
        const params: DoorLockParams = { kind: DeviceType.DOOR_LOCK, locked: locked };
        return params;
      }
      case DeviceType.FAN: {
        const fanSpeed: number | undefined = Serializer.readNumber(o, 'fanSpeed');
        if (fanSpeed === undefined) {
          return undefined;
        }
        const params: FanParams = { kind: DeviceType.FAN, fanSpeed: fanSpeed };
        return params;
      }
      case DeviceType.SOCKET: {
        const powerWatt: number | undefined = Serializer.readNumber(o, 'powerWatt');
        if (powerWatt === undefined) {
          return undefined;
        }
        const params: SocketParams = { kind: DeviceType.SOCKET, powerWatt: powerWatt };
        return params;
      }
      default:
        return undefined;
    }
  }

  private static parseSnapshot(o: Record<string, Object>): DeviceStateSnapshot | undefined {
    const deviceId: string | undefined = Serializer.readNonEmptyString(o, 'deviceId');
    const powerOn: boolean | undefined = Serializer.readBoolean(o, 'powerOn');
    const locked: boolean | undefined = Serializer.readBoolean(o, 'locked');
    const online: boolean | undefined = Serializer.readBoolean(o, 'online');
    const statusStr: string | undefined = Serializer.readString(o, 'status');
    const capturedAt: number | undefined = Serializer.readNumber(o, 'capturedAt');
    const paramsObj: Record<string, Object> | undefined = Serializer.readObject(o, 'params');
    if (deviceId === undefined || powerOn === undefined || locked === undefined ||
      online === undefined || statusStr === undefined ||
      !Serializer.inList(statusStr, DEVICE_STATUS_VALUES) || capturedAt === undefined ||
      paramsObj === undefined) {
      return undefined;
    }
    const params: DeviceParams | undefined = Serializer.parseParams(paramsObj);
    if (params === undefined) {
      return undefined;
    }
    const snapshot: DeviceStateSnapshot = {
      deviceId: deviceId,
      powerOn: powerOn,
      params: params,
      locked: locked,
      online: online,
      status: statusStr as DeviceStatus,
      capturedAt: capturedAt
    };
    return snapshot;
  }

  private static parseRule(o: Record<string, Object>): AutomationRule | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const name: string | undefined = Serializer.readNonEmptyString(o, 'name');
    const enabled: boolean | undefined = Serializer.readBoolean(o, 'enabled');
    const logicStr: string | undefined = Serializer.readString(o, 'logic');
    const priority: number | undefined = Serializer.readNumber(o, 'priority');
    const lastSatisfied: boolean | undefined = Serializer.readBoolean(o, 'lastSatisfied');
    const lastTriggeredAt: number | undefined = Serializer.readNumber(o, 'lastTriggeredAt');
    const executionCount: number | undefined = Serializer.readNumber(o, 'executionCount');
    const createdAt: number | undefined = Serializer.readNumber(o, 'createdAt');
    const updatedAt: number | undefined = Serializer.readNumber(o, 'updatedAt');
    const conditionsRaw: Object[] | undefined = Serializer.readArray(o, 'conditions');
    const actionsRaw: Object[] | undefined = Serializer.readArray(o, 'actions');
    if (id === undefined || name === undefined || enabled === undefined ||
      logicStr === undefined || !Serializer.inList(logicStr, CONDITION_LOGIC_VALUES) ||
      priority === undefined || lastSatisfied === undefined || lastTriggeredAt === undefined ||
      executionCount === undefined || createdAt === undefined || updatedAt === undefined ||
      conditionsRaw === undefined || actionsRaw === undefined) {
      return undefined;
    }
    if (conditionsRaw.length === 0 || actionsRaw.length === 0) {
      return undefined; // 规格：至少 1 条条件 + 至少 1 个动作
    }
    const conditions: AutomationCondition[] = [];
    for (let i = 0; i < conditionsRaw.length; i++) {
      const item: Object | null = conditionsRaw[i];
      if (typeof item !== 'object' || item === null) {
        return undefined;
      }
      const condition: AutomationCondition | undefined =
        Serializer.parseCondition(item as Record<string, Object>);
      if (condition === undefined) {
        return undefined;
      }
      conditions.push(condition);
    }
    const actions: AutomationAction[] = [];
    for (let i = 0; i < actionsRaw.length; i++) {
      const item: Object | null = actionsRaw[i];
      if (typeof item !== 'object' || item === null) {
        return undefined;
      }
      const action: AutomationAction | undefined =
        Serializer.parseAction(item as Record<string, Object>);
      if (action === undefined) {
        return undefined;
      }
      actions.push(action);
    }
    const rule: AutomationRule = {
      id: id,
      name: name,
      enabled: enabled,
      logic: logicStr as ConditionLogic,
      conditions: conditions,
      actions: actions,
      priority: priority,
      lastSatisfied: lastSatisfied,
      lastTriggeredAt: lastTriggeredAt,
      executionCount: executionCount,
      createdAt: createdAt,
      updatedAt: updatedAt
    };
    return rule;
  }

  private static parseCondition(o: Record<string, Object>): AutomationCondition | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const sensorStr: string | undefined = Serializer.readString(o, 'sensorType');
    const operatorStr: string | undefined = Serializer.readString(o, 'operator');
    const threshold: number | undefined = Serializer.readNumber(o, 'threshold');
    const unit: string | undefined = Serializer.readString(o, 'unit');
    if (id === undefined || sensorStr === undefined ||
      !Serializer.inList(sensorStr, SENSOR_TYPE_VALUES) || operatorStr === undefined ||
      !Serializer.inList(operatorStr, OPERATOR_VALUES) || threshold === undefined ||
      unit === undefined) {
      return undefined;
    }
    const condition: AutomationCondition = {
      id: id,
      sensorType: sensorStr as SensorType,
      operator: operatorStr as Operator,
      threshold: threshold,
      unit: unit
    };
    return condition;
  }

  private static parseAction(o: Record<string, Object>): AutomationAction | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const targetDeviceId: string | undefined = Serializer.readNonEmptyString(o, 'targetDeviceId');
    const commandStr: string | undefined = Serializer.readString(o, 'command');
    const order: number | undefined = Serializer.readNumber(o, 'order');
    if (id === undefined || targetDeviceId === undefined || commandStr === undefined ||
      !Serializer.inList(commandStr, DEVICE_COMMAND_VALUES) || order === undefined) {
      return undefined;
    }
    const raw: Object = o['value'];
    let value: number | boolean | ACMode | undefined = undefined;
    if (typeof raw === 'number') {
      value = raw;
    } else if (typeof raw === 'boolean') {
      value = raw;
    } else if (typeof raw === 'string' && Serializer.inList(raw, AC_MODE_VALUES)) {
      value = raw as ACMode;
    }
    if (value === undefined) {
      return undefined;
    }
    const action: AutomationAction = {
      id: id,
      targetDeviceId: targetDeviceId,
      command: commandStr as DeviceCommand,
      value: value,
      order: order
    };
    return action;
  }

  private static parseScene(o: Record<string, Object>): Scene | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const name: string | undefined = Serializer.readNonEmptyString(o, 'name');
    const typeStr: string | undefined = Serializer.readString(o, 'type');
    const isPreset: boolean | undefined = Serializer.readBoolean(o, 'isPreset');
    const createdAt: number | undefined = Serializer.readNumber(o, 'createdAt');
    const updatedAt: number | undefined = Serializer.readNumber(o, 'updatedAt');
    const statesRaw: Object[] | undefined = Serializer.readArray(o, 'deviceStates');
    const returnRaw: Object[] | undefined = Serializer.readArray(o, 'returnSnapshot');
    if (id === undefined || name === undefined || typeStr === undefined ||
      !Serializer.inList(typeStr, SCENE_TYPE_VALUES) || isPreset === undefined ||
      createdAt === undefined || updatedAt === undefined || statesRaw === undefined ||
      returnRaw === undefined) {
      return undefined;
    }
    const deviceStates: DeviceStateSnapshot[] = [];
    for (let i = 0; i < statesRaw.length; i++) {
      const item: Object | null = statesRaw[i];
      if (typeof item !== 'object' || item === null) {
        return undefined;
      }
      const snapshot: DeviceStateSnapshot | undefined =
        Serializer.parseSnapshot(item as Record<string, Object>);
      if (snapshot === undefined) {
        return undefined;
      }
      deviceStates.push(snapshot);
    }
    const returnSnapshot: DeviceStateSnapshot[] = [];
    for (let i = 0; i < returnRaw.length; i++) {
      const item: Object | null = returnRaw[i];
      if (typeof item !== 'object' || item === null) {
        return undefined;
      }
      const snapshot: DeviceStateSnapshot | undefined =
        Serializer.parseSnapshot(item as Record<string, Object>);
      if (snapshot === undefined) {
        return undefined;
      }
      returnSnapshot.push(snapshot);
    }
    const scene: Scene = {
      id: id,
      name: name,
      type: typeStr as SceneType,
      deviceStates: deviceStates,
      isPreset: isPreset,
      returnSnapshot: returnSnapshot,
      createdAt: createdAt,
      updatedAt: updatedAt
    };
    return scene;
  }

  private static parseEnvironment(o: Record<string, Object>): EnvironmentData | undefined {
    const temperature: number | undefined = Serializer.readNumber(o, 'temperature');
    const humidity: number | undefined = Serializer.readNumber(o, 'humidity');
    const illuminance: number | undefined = Serializer.readNumber(o, 'illuminance');
    const airQuality: number | undefined = Serializer.readNumber(o, 'airQuality');
    const humanPresence: boolean | undefined = Serializer.readBoolean(o, 'humanPresence');
    const timestamp: number | undefined = Serializer.readNumber(o, 'timestamp');
    const sourceStr: string | undefined = Serializer.readString(o, 'source');
    if (temperature === undefined || humidity === undefined || illuminance === undefined ||
      airQuality === undefined || humanPresence === undefined || timestamp === undefined ||
      sourceStr === undefined || !Serializer.inList(sourceStr, ENV_SOURCE_VALUES)) {
      return undefined;
    }
    const environment: EnvironmentData = {
      temperature: temperature,
      humidity: humidity,
      illuminance: illuminance,
      airQuality: airQuality,
      humanPresence: humanPresence,
      timestamp: timestamp,
      source: sourceStr as EnvSource
    };
    return environment;
  }

  private static parseSettings(o: Record<string, Object>): AppSettings | undefined {
    const automationEnabled: boolean | undefined = Serializer.readBoolean(o, 'automationEnabled');
    const simulationEnabled: boolean | undefined = Serializer.readBoolean(o, 'simulationEnabled');
    const sampleIntervalMs: number | undefined = Serializer.readNumber(o, 'sampleIntervalMs');
    const logLimit: number | undefined = Serializer.readNumber(o, 'logLimit');
    const schemaVersion: number | undefined = Serializer.readNumber(o, 'schemaVersion');
    const appVersion: string | undefined = Serializer.readString(o, 'appVersion');
    if (automationEnabled === undefined || simulationEnabled === undefined ||
      sampleIntervalMs === undefined || logLimit === undefined || schemaVersion === undefined ||
      appVersion === undefined) {
      return undefined;
    }
    const settings: AppSettings = {
      automationEnabled: automationEnabled,
      simulationEnabled: simulationEnabled,
      sampleIntervalMs: sampleIntervalMs,
      logLimit: logLimit,
      schemaVersion: schemaVersion,
      appVersion: appVersion
    };
    return settings;
  }

  private static parseOperationLog(o: Record<string, Object>): OperationLog | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const timestamp: number | undefined = Serializer.readNumber(o, 'timestamp');
    const actorStr: string | undefined = Serializer.readString(o, 'actor');
    const deviceId: string | undefined = Serializer.readString(o, 'deviceId');
    const action: string | undefined = Serializer.readString(o, 'action');
    const before: string | undefined = Serializer.readString(o, 'before');
    const after: string | undefined = Serializer.readString(o, 'after');
    const resultStr: string | undefined = Serializer.readString(o, 'result');
    const message: string | undefined = Serializer.readString(o, 'message');
    if (id === undefined || timestamp === undefined || actorStr === undefined ||
      !Serializer.inList(actorStr, LOG_ACTOR_VALUES) || deviceId === undefined ||
      action === undefined || before === undefined || after === undefined ||
      resultStr === undefined || !Serializer.inList(resultStr, RESULT_CODE_VALUES) ||
      message === undefined) {
      return undefined;
    }
    const log: OperationLog = {
      id: id,
      timestamp: timestamp,
      actor: actorStr as LogActor,
      deviceId: deviceId,
      action: action,
      before: before,
      after: after,
      result: resultStr as ResultCode,
      message: message
    };
    return log;
  }

  private static parseActionDetail(o: Record<string, Object>): ActionExecutionDetail | undefined {
    const actionId: string | undefined = Serializer.readString(o, 'actionId');
    const targetDeviceId: string | undefined = Serializer.readString(o, 'targetDeviceId');
    const command: string | undefined = Serializer.readString(o, 'command');
    const value: string | undefined = Serializer.readString(o, 'value');
    const resultStr: string | undefined = Serializer.readString(o, 'result');
    const message: string | undefined = Serializer.readString(o, 'message');
    if (actionId === undefined || targetDeviceId === undefined || command === undefined ||
      value === undefined || resultStr === undefined ||
      !Serializer.inList(resultStr, RESULT_CODE_VALUES) || message === undefined) {
      return undefined;
    }
    const detail: ActionExecutionDetail = {
      actionId: actionId,
      targetDeviceId: targetDeviceId,
      command: command,
      value: value,
      result: resultStr as ResultCode,
      message: message
    };
    return detail;
  }

  private static parseRuleExecLog(o: Record<string, Object>): RuleExecutionLog | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const timestamp: number | undefined = Serializer.readNumber(o, 'timestamp');
    const ruleId: string | undefined = Serializer.readString(o, 'ruleId');
    const ruleName: string | undefined = Serializer.readString(o, 'ruleName');
    const statusStr: string | undefined = Serializer.readString(o, 'status');
    const errorMsg: string | undefined = Serializer.readString(o, 'errorMsg');
    const durationMs: number | undefined = Serializer.readNumber(o, 'durationMs');
    const snapshotObj: Record<string, Object> | undefined = Serializer.readObject(o, 'snapshot');
    const matchedRaw: Object[] | undefined = Serializer.readArray(o, 'matchedConditions');
    const executedRaw: Object[] | undefined = Serializer.readArray(o, 'executedActions');
    const skippedRaw: Object[] | undefined = Serializer.readArray(o, 'skippedActions');
    if (id === undefined || timestamp === undefined || ruleId === undefined ||
      ruleName === undefined || statusStr === undefined ||
      !Serializer.inList(statusStr, RULE_EXEC_STATUS_VALUES) || errorMsg === undefined ||
      durationMs === undefined || snapshotObj === undefined || matchedRaw === undefined ||
      executedRaw === undefined || skippedRaw === undefined) {
      return undefined;
    }
    const snapshot: EnvironmentData | undefined = Serializer.parseEnvironment(snapshotObj);
    if (snapshot === undefined) {
      return undefined;
    }
    const matched: AutomationCondition[] = [];
    for (let i = 0; i < matchedRaw.length; i++) {
      const item: Object | null = matchedRaw[i];
      if (typeof item !== 'object' || item === null) {
        return undefined;
      }
      const condition: AutomationCondition | undefined =
        Serializer.parseCondition(item as Record<string, Object>);
      if (condition === undefined) {
        return undefined;
      }
      matched.push(condition);
    }
    const executed: ActionExecutionDetail[] = [];
    for (let i = 0; i < executedRaw.length; i++) {
      const item: Object | null = executedRaw[i];
      if (typeof item !== 'object' || item === null) {
        return undefined;
      }
      const detail: ActionExecutionDetail | undefined =
        Serializer.parseActionDetail(item as Record<string, Object>);
      if (detail === undefined) {
        return undefined;
      }
      executed.push(detail);
    }
    const skipped: ActionExecutionDetail[] = [];
    for (let i = 0; i < skippedRaw.length; i++) {
      const item: Object | null = skippedRaw[i];
      if (typeof item !== 'object' || item === null) {
        return undefined;
      }
      const detail: ActionExecutionDetail | undefined =
        Serializer.parseActionDetail(item as Record<string, Object>);
      if (detail === undefined) {
        return undefined;
      }
      skipped.push(detail);
    }
    const log: RuleExecutionLog = {
      id: id,
      timestamp: timestamp,
      ruleId: ruleId,
      ruleName: ruleName,
      snapshot: snapshot,
      matchedConditions: matched,
      executedActions: executed,
      skippedActions: skipped,
      status: statusStr as RuleExecStatus,
      errorMsg: errorMsg,
      durationMs: durationMs
    };
    return log;
  }

  private static parseEnvironmentLog(o: Record<string, Object>): EnvironmentLog | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const timestamp: number | undefined = Serializer.readNumber(o, 'timestamp');
    const sensorStr: string | undefined = Serializer.readString(o, 'sensorType');
    const sourceStr: string | undefined = Serializer.readString(o, 'source');
    if (id === undefined || timestamp === undefined || sensorStr === undefined ||
      !Serializer.inList(sensorStr, SENSOR_TYPE_VALUES) || sourceStr === undefined ||
      !Serializer.inList(sourceStr, ENV_SOURCE_VALUES)) {
      return undefined;
    }
    const before: number | boolean | undefined = Serializer.readNumberOrBoolean(o, 'before');
    const after: number | boolean | undefined = Serializer.readNumberOrBoolean(o, 'after');
    if (before === undefined || after === undefined) {
      return undefined;
    }
    const log: EnvironmentLog = {
      id: id,
      timestamp: timestamp,
      sensorType: sensorStr as SensorType,
      before: before,
      after: after,
      source: sourceStr as EnvSource
    };
    return log;
  }

  private static parseSceneSwitchLog(o: Record<string, Object>): SceneSwitchLog | undefined {
    const id: string | undefined = Serializer.readNonEmptyString(o, 'id');
    const timestamp: number | undefined = Serializer.readNumber(o, 'timestamp');
    const fromSceneId: string | undefined = Serializer.readString(o, 'fromSceneId');
    const toSceneId: string | undefined = Serializer.readString(o, 'toSceneId');
    const appliedCount: number | undefined = Serializer.readNumber(o, 'appliedCount');
    const failedCount: number | undefined = Serializer.readNumber(o, 'failedCount');
    if (id === undefined || timestamp === undefined || fromSceneId === undefined ||
      toSceneId === undefined || appliedCount === undefined || failedCount === undefined) {
      return undefined;
    }
    const log: SceneSwitchLog = {
      id: id,
      timestamp: timestamp,
      fromSceneId: fromSceneId,
      toSceneId: toSceneId,
      appliedCount: appliedCount,
      failedCount: failedCount
    };
    return log;
  }

  // ——————————————————————————————————————————————————————————
  // 读字段原语（每个都做真实 `typeof` 校验，不做强转）
  // ——————————————————————————————————————————————————————————

  /** `JSON.parse` + 「确实是对象」校验；失败返回 undefined，绝不抛。 */
  private static asObject(raw: string): Record<string, Object> | undefined {
    if (!raw) {
      return undefined;
    }
    try {
      const parsed: Object | null = JSON.parse(raw);
      if (typeof parsed !== 'object' || parsed === null) {
        return undefined;
      }
      return parsed as Record<string, Object>;
    } catch (err) {
      return undefined;
    }
  }

  private static readString(o: Record<string, Object>, key: string): string | undefined {
    const value: Object = o[key];
    if (typeof value === 'string') {
      return value;
    }
    return undefined;
  }

  private static readNonEmptyString(o: Record<string, Object>, key: string): string | undefined {
    const value: string | undefined = Serializer.readString(o, key);
    if (value === undefined || value.length === 0) {
      return undefined;
    }
    return value;
  }

  private static readNumber(o: Record<string, Object>, key: string): number | undefined {
    const value: Object = o[key];
    if (typeof value === 'number' && isFinite(value)) {
      return value;
    }
    return undefined;
  }

  private static readBoolean(o: Record<string, Object>, key: string): boolean | undefined {
    const value: Object = o[key];
    if (typeof value === 'boolean') {
      return value;
    }
    return undefined;
  }

  private static readNumberOrBoolean(o: Record<string, Object>,
    key: string): number | boolean | undefined {
    const value: Object = o[key];
    if (typeof value === 'number' && isFinite(value)) {
      return value;
    }
    if (typeof value === 'boolean') {
      return value;
    }
    return undefined;
  }

  private static readArray(o: Record<string, Object>, key: string): Object[] | undefined {
    const value: Object = o[key];
    if (Array.isArray(value)) {
      return value as Object[];
    }
    return undefined;
  }

  private static readObject(o: Record<string, Object>,
    key: string): Record<string, Object> | undefined {
    const value: Object | null = o[key];
    if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
      return value as Record<string, Object>;
    }
    return undefined;
  }

  /** 白名单校验（枚举字面量逐个列出，不用 `Object.values`）。 */
  private static inList(value: string, list: string[]): boolean {
    return list.indexOf(value) >= 0;
  }

  /** 分区名白名单校验（块头 `p` 字段）。 */
  private static inPartitionList(value: string): boolean {
    return Serializer.inList(value, [
      StoragePartition.META, StoragePartition.DEVICES, StoragePartition.RULES,
      StoragePartition.SCENES, StoragePartition.SETTINGS, StoragePartition.ENVIRONMENT,
      StoragePartition.OPERATION_LOGS, StoragePartition.RULE_EXEC_LOGS,
      StoragePartition.ENVIRONMENT_LOGS, StoragePartition.RETURN_SNAPSHOT
    ]);
  }

  private static ok<T>(data: T, dropped: number): DecodeResult<T> {
    const result: DecodeResult<T> = {
      ok: true,
      data: data,
      error: '',
      dropped: dropped
    };
    return result;
  }

  private static fail<T>(error: string, dropped: number): DecodeResult<T> {
    const result: DecodeResult<T> = {
      ok: false,
      error: error,
      dropped: dropped
    };
    return result;
  }
}
