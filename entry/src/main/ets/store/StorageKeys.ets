/**
 * 智寓 · 持久化键常量与分块键工具（设计 8.1 命名规范 / 8.6.1 / MI-19 / Q-01）
 *
 * 键分层（`MAX_KEY_LENGTH` = 80，`api/@ohos.data.preferences.d.ts` 第 112 行）：
 *   ① 标量键：直接写基键本身，不分块无块头
 *      `KEY-01 smartdorm.meta.schemaVersion`（标量字符串版本号）、
 *      `KEY-11 smartdorm.meta.runtime`（运行时元信息 JSON）；
 *   ② 分区块键：`KEY-02`~`KEY-10` 的基键**不落任何值**，只作命名基，
 *      实际写入 `<base>.hdr`（块头，提交点）与 `<base>.cNNNN`（数据块，4 位零填充）。
 *
 * 为什么必须分块（不是优化，是可行性前提）：preferences 单值上限 8192 字符
 * （同文件第 145 行 `MAX_VALUE_LENGTH`），日志满载时 JSON 约 1.30 MB。
 * 「一个分区一个键」在日志累积到约 55 条时即抛 401，且抛在后台 flush 里——静默、滞后。
 *
 * 本类**零 `@kit.*` 依赖**（仅引入零 Kit 的 `CHUNK_INDEX_MAX`），因此键拼接与解析
 * 可在 Node 侧 L2 单测（任务列表-第四阶段 §7 第 14 项）。
 *
 * 依据：design/任务列表-第四阶段.md 1.1、1.1.2、2.1、4.7。
 */
import { CHUNK_INDEX_MAX } from '../common/Constants';

/** 十个逻辑分区。阶段四**不扩值**（META 用两把标量键承载，见 `writeMeta()` 分支）。 */
export enum StoragePartition {
  META = 'META',
  DEVICES = 'DEVICES',
  RULES = 'RULES',
  SCENES = 'SCENES',
  SETTINGS = 'SETTINGS',
  ENVIRONMENT = 'ENVIRONMENT',
  OPERATION_LOGS = 'OPERATION_LOGS',
  RULE_EXEC_LOGS = 'RULE_EXEC_LOGS',
  ENVIRONMENT_LOGS = 'ENVIRONMENT_LOGS',
  RETURN_SNAPSHOT = 'RETURN_SNAPSHOT'
}

/**
 * 块头结构（**提交点**）。
 *
 * 放在 `StorageKeys` 而不是 `Serializer`，是为了让 T4-01 的 `WriteQueue`
 * 能自行构造块头而**不反向依赖 T4-02**（任务列表-第四阶段 §4.7 注）。
 *
 * 字段名全短以减少体积：`p` 分区 / `n` 块数 / `t` savedAt(epoch ms) / `v` 块格式版本。
 * `n` 是提交点语义：块头指向 n 块且 n 块已齐 → 新数据生效；否则按旧 n 读旧块。
 */
export interface ChunkHeader {
  p: StoragePartition;
  n: number;
  t: number;
  v: number;
}

/** 块键中缀与块序号位数（`c0000` ~ `c9999`，4 位零填充写死）。 */
const CHUNK_INFIX: string = '.c';
const CHUNK_INDEX_DIGITS: number = 4;
const HEADER_SUFFIX: string = '.hdr';

export class StorageKeys {
  // ——————————————————————————————————————————————————————————
  // 键定义
  // ——————————————————————————————————————————————————————————

  static readonly KEY_01_SCHEMA_VERSION: string = 'smartdorm.meta.schemaVersion';
  static readonly KEY_02_DEVICES: string = 'smartdorm.devices';
  static readonly KEY_03_RULES: string = 'smartdorm.rules';
  static readonly KEY_04_SCENES: string = 'smartdorm.scenes';
  static readonly KEY_05_SETTINGS: string = 'smartdorm.settings';
  static readonly KEY_06_ENVIRONMENT: string = 'smartdorm.environment';
  static readonly KEY_07_OPERATION_LOGS: string = 'smartdorm.logs.operation';
  static readonly KEY_08_RULE_EXEC_LOGS: string = 'smartdorm.logs.ruleExec';
  static readonly KEY_09_ENVIRONMENT_LOGS: string = 'smartdorm.logs.environment';
  static readonly KEY_10_RETURN_SNAPSHOT: string = 'smartdorm.state.returnSnapshot';

  /**
   * `KEY-11` 运行时元信息（§2.3 偏差 ②）。
   * 承载 `currentSceneId` / `currentMode` / `firstLaunchAt` / `lastLaunchAt` / `bootCount`：
   * `KEY-01` 是标量版本号，没有任何键承载这几个顶层指针，而 `bootCount`
   * 是「恢复 vs 重生成」的最强判据（TC-N-07）。
   */
  static readonly KEY_11_RUNTIME: string = 'smartdorm.meta.runtime';

  /** 十一把逻辑键全量列表（供证据文件与设置页诊断按名遍历）。 */
  static readonly ALL: string[] = [
    StorageKeys.KEY_01_SCHEMA_VERSION,
    StorageKeys.KEY_02_DEVICES,
    StorageKeys.KEY_03_RULES,
    StorageKeys.KEY_04_SCENES,
    StorageKeys.KEY_05_SETTINGS,
    StorageKeys.KEY_06_ENVIRONMENT,
    StorageKeys.KEY_07_OPERATION_LOGS,
    StorageKeys.KEY_08_RULE_EXEC_LOGS,
    StorageKeys.KEY_09_ENVIRONMENT_LOGS,
    StorageKeys.KEY_10_RETURN_SNAPSHOT,
    StorageKeys.KEY_11_RUNTIME
  ];

  /** 标量键组：直接写基键本身，不分块、无块头。 */
  static readonly SCALAR_KEYS: string[] = [
    StorageKeys.KEY_01_SCHEMA_VERSION,
    StorageKeys.KEY_11_RUNTIME
  ];

  /** 分块基键组：基键本身不落值，只写 `<base>.hdr` 与 `<base>.cNNNN`。 */
  static readonly CHUNKED_BASES: string[] = [
    StorageKeys.KEY_02_DEVICES,
    StorageKeys.KEY_03_RULES,
    StorageKeys.KEY_04_SCENES,
    StorageKeys.KEY_05_SETTINGS,
    StorageKeys.KEY_06_ENVIRONMENT,
    StorageKeys.KEY_07_OPERATION_LOGS,
    StorageKeys.KEY_08_RULE_EXEC_LOGS,
    StorageKeys.KEY_09_ENVIRONMENT_LOGS,
    StorageKeys.KEY_10_RETURN_SNAPSHOT
  ];

  // ——————————————————————————————————————————————————————————
  // 分区 ↔ 键
  // ——————————————————————————————————————————————————————————

  /**
   * 分区 → 基键。
   *
   * `META` 是**标量键组**（同时写 `KEY-01` 与 `KEY-11`），不走分块路径，
   * 这里返回 `KEY_01` 仅作防御性默认值；调用方必须先判 `isChunked()`。
   */
  static baseOfPartition(p: StoragePartition): string {
    switch (p) {
      case StoragePartition.DEVICES:
        return StorageKeys.KEY_02_DEVICES;
      case StoragePartition.RULES:
        return StorageKeys.KEY_03_RULES;
      case StoragePartition.SCENES:
        return StorageKeys.KEY_04_SCENES;
      case StoragePartition.SETTINGS:
        return StorageKeys.KEY_05_SETTINGS;
      case StoragePartition.ENVIRONMENT:
        return StorageKeys.KEY_06_ENVIRONMENT;
      case StoragePartition.OPERATION_LOGS:
        return StorageKeys.KEY_07_OPERATION_LOGS;
      case StoragePartition.RULE_EXEC_LOGS:
        return StorageKeys.KEY_08_RULE_EXEC_LOGS;
      case StoragePartition.ENVIRONMENT_LOGS:
        return StorageKeys.KEY_09_ENVIRONMENT_LOGS;
      case StoragePartition.RETURN_SNAPSHOT:
        return StorageKeys.KEY_10_RETURN_SNAPSHOT;
      default:
        return StorageKeys.KEY_01_SCHEMA_VERSION;
    }
  }

  /** 该分区是否走「块头 + 数据块」路径（`META` 走标量键分支，返回 false）。 */
  static isChunked(p: StoragePartition): boolean {
    return p !== StoragePartition.META;
  }

  /** 块头键：`<base>.hdr`（长度 ≤ 35，远低于 80 上限）。 */
  static headerKey(base: string): string {
    return base + HEADER_SUFFIX;
  }

  /**
   * 块键：`<base>.c` + **4 位零填充**序号（长度 ≤ 37）。
   *
   * `index` 越界（<0 / >`CHUNK_INDEX_MAX` / 非整数）**抛错拒绝**，
   * 不得退化成 5 位序号——否则 `chunkIndexOf` 的解析规则被破坏（§2.1）。
   */
  static chunkKey(base: string, index: number): string {
    if (index < 0 || index > CHUNK_INDEX_MAX || Math.floor(index) !== index) {
      throw new Error('块序号非法（要求 0~' + CHUNK_INDEX_MAX + ' 的整数）：' + index);
    }
    let digits: string = index.toString();
    while (digits.length < CHUNK_INDEX_DIGITS) {
      digits = '0' + digits;
    }
    return base + CHUNK_INFIX + digits;
  }

  /**
   * 块键 → 块序号；**非本基键的块一律返回 -1**。
   *
   * 四条边界（§2.1 写死，L2 判据 A2）：
   *   ① `<base>.hdr` → -1（后缀不是 `.c`）；
   *   ② `<base>.c12`（位数不足）→ -1；
   *   ③ `<otherBase>.c0001` → -1（前缀不匹配）；
   *   ④ 只有 4 位全数字后缀才返回序号。
   */
  static chunkIndexOf(key: string, base: string): number {
    const prefix: string = base + CHUNK_INFIX;
    if (!key.startsWith(prefix)) {
      return -1;
    }
    const suffix: string = key.substring(prefix.length);
    if (suffix.length !== CHUNK_INDEX_DIGITS) {
      return -1;
    }
    let index: number = 0;
    for (let i = 0; i < suffix.length; i++) {
      const code: number = suffix.charCodeAt(i);
      if (code < 48 || code > 57) {
        return -1;
      }
      index = index * 10 + (code - 48);
    }
    if (index > CHUNK_INDEX_MAX) {
      return -1;
    }
    return index;
  }
}
