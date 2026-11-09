/**
 * 智寓 · 工程级常量（PRD 4.3 / 4.4 参数基线、Q-12 日志容量、NFR-05 采样间隔）
 * 依据：design/系统架构设计.md 3.14 节、8.4 节。逐项与 PRD 基线一致，未擅自改动。
 */
export const SCHEMA_VERSION: number = 1;
export const STORE_NAME: string = 'smartdorm_store';
export const DEFAULT_SAMPLE_INTERVAL_MS: number = 4000;
export const DEFAULT_LOG_LIMIT: number = 1000;
export const ENV_LOG_LIMIT_FACTOR: number = 2; // EnvironmentLog 上限 = logLimit × 2 = 2000
export const SCENE_LOG_LIMIT: number = 500; // 固定上限
export const EXPORT_DIR_NAME: string = 'exports';
export const APP_VERSION: string = '1.0.0';

/** 数值参数合法区间（纯数据，Node 侧可单测）。 */
export interface NumericRange {
  min: number;
  max: number;
  integer: boolean;
}

export interface RangeTable {
  BRIGHTNESS: NumericRange;
  AC_TEMPERATURE: NumericRange;
  OPEN_PERCENT: NumericRange;
  FAN_SPEED: NumericRange;
  POWER_WATT: NumericRange;
  TEMPERATURE: NumericRange;
  HUMIDITY: NumericRange;
  ILLUMINANCE: NumericRange;
  AIR_QUALITY: NumericRange;
}

// ———————————————————————————————————————————————————————————————
// 阶段四 · 持久化块写入常量（design/任务列表-第四阶段.md §2.2，共 8 个）
//
// 依据：`api/@ohos.data.preferences.d.ts` 第 145 行 `MAX_VALUE_LENGTH` = 8192 字符、
// 第 112 行 `MAX_KEY_LENGTH` = 80 字符。日志满载 JSON 约 1.30 MB，远超单值上限，
// 因此「一分区一键」不可行，必须按条目边界分块（§1.1 裁决 1/2）。
// ———————————————————————————————————————————————————————————————

/** 每块 JSON 上限：对 8192 留 14.6% 余量，容纳中文与转义膨胀。 */
export const CHUNK_MAX_CHARS: number = 7000;

/** 块格式版本（§1.3：块头带 `v`，当前 1）。升级块格式必须同时升 `SCHEMA_VERSION`。 */
export const CHUNK_FORMAT_VERSION: number = 1;

/** 单条目上限：超过则该条不落盘（内存态保留），避免一条超长日志把整分区写失败。 */
export const ENTRY_GUARD_CHARS: number = 6500;

/** 块序号上限：块键固定 4 位零填充，故 `c0000` ~ `c9999`。 */
export const CHUNK_INDEX_MAX: number = 9999;

/** 用户车道合并窗口：点按后 200 ms 内同一次交互的多分区写合并成一批。 */
export const FLUSH_DEBOUNCE_USER_MS: number = 200;

/** 日志车道合并窗口：采样每 4 s 追加一条环境日志，不能每次都重写数百分块。 */
export const FLUSH_DEBOUNCE_LOG_MS: number = 30000;

/** 日志车道次数兜底：累计 20 次日志写先到者触发，防止窗口内持续采样把落盘无限推迟。 */
export const FLUSH_MAX_PENDING_LOG_WRITES: number = 20;

/** 连续失败多少次后，设置页显示常驻持久化告警条。 */
export const FLUSH_FAIL_WARN_STREAK: number = 3;

/** 内存诊断环形缓冲上限（诊断不落盘，避免「写失败→记日志→又写失败」的自噬循环）。 */
export const DIAGNOSTIC_CAPACITY: number = 50;

export const RANGE: RangeTable = {
  BRIGHTNESS: { min: 0, max: 100, integer: true },
  AC_TEMPERATURE: { min: 16, max: 30, integer: true },
  OPEN_PERCENT: { min: 0, max: 100, integer: true },
  FAN_SPEED: { min: 1, max: 3, integer: true },
  POWER_WATT: { min: 0, max: 2500, integer: false },
  TEMPERATURE: { min: -10, max: 50, integer: false },
  HUMIDITY: { min: 0, max: 100, integer: false },
  ILLUMINANCE: { min: 0, max: 10000, integer: false },
  AIR_QUALITY: { min: 0, max: 500, integer: false }
};
