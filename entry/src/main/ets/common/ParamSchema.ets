/**
 * 智寓 · 参数合法范围表与纯函数校验（FR-02-10 / FR-03-09 / 设计 8.4）
 * 依据：design/系统架构设计.md 3.14 节常量表、4.1 节 MI-03。
 * 纯函数，无系统 API 依赖，可在 Node 侧单测（TC-B / TC-N）。
 */
import { DeviceType, ParamKey, ResultCode, ACMode, SensorType } from '../model/Enums';
import { ParamValue, DeviceParamsFactory } from '../model/DeviceParams';
import { RANGE, NumericRange } from './Constants';

/** ParamKey → 数值区间映射（布尔 / 枚举型键不在此表）。 */
export const PARAM_RANGE: Record<string, NumericRange> = {
  brightness: RANGE.BRIGHTNESS,
  temperature: RANGE.AC_TEMPERATURE,
  openPercent: RANGE.OPEN_PERCENT,
  fanSpeed: RANGE.FAN_SPEED,
  powerWatt: RANGE.POWER_WATT
};

/** 传感器 → 数值区间映射（布尔型 HUMAN_PRESENCE 不在此表）。 */
export const SENSOR_RANGE: Record<string, NumericRange> = {
  TEMPERATURE: RANGE.TEMPERATURE,
  HUMIDITY: RANGE.HUMIDITY,
  ILLUMINANCE: RANGE.ILLUMINANCE,
  AIR_QUALITY: RANGE.AIR_QUALITY
};

/** 是否为合法空调模式值。 */
export function isACMode(value: ParamValue): boolean {
  if (typeof value !== 'string') {
    return false;
  }
  return (
    value === ACMode.COOL ||
    value === ACMode.HEAT ||
    value === ACMode.FAN ||
    value === ACMode.DRY ||
    value === ACMode.AUTO
  );
}

/** 数值是否在区间内（含整数约束）。 */
export function isInRange(value: number, range: NumericRange): boolean {
  if (Number.isNaN(value) || value < range.min || value > range.max) {
    return false;
  }
  if (range.integer && Math.floor(value) !== value) {
    return false;
  }
  return true;
}

/** 把数值钳制到合法区间（FR-03-09 允许的降级处理）。 */
export function clampToRange(value: number, range: NumericRange): number {
  let result: number = value;
  if (result < range.min) {
    result = range.min;
  }
  if (result > range.max) {
    result = range.max;
  }
  if (range.integer) {
    result = Math.round(result);
  }
  return result;
}

/** 只校验值本身（类型 + 区间），不依赖设备类型；阶段二契约占位用。 */
export function validateParamValue(key: ParamKey, value: ParamValue): ResultCode {
  switch (key) {
    case ParamKey.MODE:
      return isACMode(value) ? ResultCode.OK : ResultCode.INVALID_PARAM;
    case ParamKey.LOCKED:
      return typeof value === 'boolean' ? ResultCode.OK : ResultCode.INVALID_PARAM;
    default: {
      if (typeof value !== 'number') {
        return ResultCode.INVALID_PARAM;
      }
      const range: NumericRange = PARAM_RANGE[key];
      return isInRange(value, range) ? ResultCode.OK : ResultCode.INVALID_PARAM;
    }
  }
}

/** MI-03 前置校验：参数键适用于该设备类型吗，值类型与范围合法吗。 */
export function validateParam(type: DeviceType, key: ParamKey, value: ParamValue): ResultCode {
  const keys: ParamKey[] = DeviceParamsFactory.paramKeysOf(type);
  if (keys.indexOf(key) < 0) {
    return ResultCode.INVALID_PARAM;
  }
  return validateParamValue(key, value);
}

/** MI-08 前置校验：传感器取值类型与范围合法吗。 */
export function validateSensorValue(sensorType: SensorType, value: number | boolean): ResultCode {
  if (sensorType === SensorType.HUMAN_PRESENCE) {
    return typeof value === 'boolean' ? ResultCode.OK : ResultCode.INVALID_PARAM;
  }
  if (typeof value !== 'number') {
    return ResultCode.INVALID_PARAM;
  }
  const range: NumericRange = SENSOR_RANGE[sensorType];
  return isInRange(value, range) ? ResultCode.OK : ResultCode.INVALID_PARAM;
}
