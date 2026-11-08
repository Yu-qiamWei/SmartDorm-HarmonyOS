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
