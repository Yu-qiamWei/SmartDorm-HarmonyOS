/**
 * 智寓 · 领域枚举总表（全部 string enum，保证 JSON 序列化后可迁移）
 *
 * 依据：design/系统架构设计.md 3.2 节（11 个 PRD 9.9 枚举 + 3 个设计补充枚举）、
 * 4.1 节支撑类型（ResetScope / LogType）。StoragePartition 定义在 store/StorageKeys.ets。
 * 命名消歧：ResultCode.CONFLICT_SKIPPED（命令结果码）与 RuleExecStatus.SKIPPED_CONFLICT
 * （执行日志状态）分属两个不同枚举，不得混用（设计 3.2 节 / 第 12 章修订建议 8）。
 */

/** 六类设备（FR-02 / PRD 4.3）。 */
export enum DeviceType {
  LIGHT = 'LIGHT',
  AIR_CONDITIONER = 'AIR_CONDITIONER',
  CURTAIN = 'CURTAIN',
  DOOR_LOCK = 'DOOR_LOCK',
  FAN = 'FAN',
  SOCKET = 'SOCKET'
}

/** 设备四态：RUNNING / IDLE / FAULT / OFFLINE（FR-01-06 异常数来源）。 */
export enum DeviceStatus {
  RUNNING = 'RUNNING',
  IDLE = 'IDLE',
  FAULT = 'FAULT',
  OFFLINE = 'OFFLINE'
}

/** 12 类设备命令（FR-04-04 / DM-05）。 */
export enum DeviceCommand {
  POWER_ON = 'POWER_ON',
  POWER_OFF = 'POWER_OFF',
  SET_BRIGHTNESS = 'SET_BRIGHTNESS',
  SET_TEMPERATURE = 'SET_TEMPERATURE',
  SET_MODE = 'SET_MODE',
  SET_OPEN_PERCENT = 'SET_OPEN_PERCENT',
  LOCK = 'LOCK',
  UNLOCK = 'UNLOCK',
  SET_FAN_SPEED = 'SET_FAN_SPEED',
  SET_POWER = 'SET_POWER',
  SOCKET_ON = 'SOCKET_ON',
  SOCKET_OFF = 'SOCKET_OFF'
}

/** 五类传感器（FR-03 / PRD 4.4）。 */
export enum SensorType {
  TEMPERATURE = 'TEMPERATURE',
  HUMIDITY = 'HUMIDITY',
  ILLUMINANCE = 'ILLUMINANCE',
  AIR_QUALITY = 'AIR_QUALITY',
  HUMAN_PRESENCE = 'HUMAN_PRESENCE'
}

/** 条件运算符（FR-04-02）。 */
export enum Operator {
  GT = 'GT',
  LT = 'LT',
  IS_TRUE = 'IS_TRUE',
  IS_FALSE = 'IS_FALSE'
}

/** P0 固定 AND（OR 为 P2-01 扩展）。 */
export enum ConditionLogic {
  AND = 'AND'
}

/** 场景类型（FR-05-01 四预置 + 自定义）。 */
export enum SceneType {
  STUDY = 'STUDY',
  SLEEP = 'SLEEP',
  AWAY = 'AWAY',
  RETURN = 'RETURN',
  CUSTOM = 'CUSTOM'
}

/** 日志发起方（FR-06-01）。 */
export enum LogActor {
  USER = 'USER',
  RULE = 'RULE',
  SCENE = 'SCENE',
  SYSTEM = 'SYSTEM'
}

/** 规则执行状态（DM-08 / PRD 9.8）。 */
export enum RuleExecStatus {
  SUCCESS = 'SUCCESS',
  PARTIAL = 'PARTIAL',
  FAILED = 'FAILED',
  SKIPPED_DEDUP = 'SKIPPED_DEDUP',
  SKIPPED_CONFLICT = 'SKIPPED_CONFLICT',
  SKIPPED_DISABLED = 'SKIPPED_DISABLED'
}

/** 环境数据来源（DM-02）。 */
export enum EnvSource {
  MANUAL = 'MANUAL',
  SIMULATED = 'SIMULATED',
  INIT = 'INIT'
}

/** 统一命令结果码（PRD 8.5）。 */
export enum ResultCode {
  OK = 'OK',
  NO_CHANGE = 'NO_CHANGE',
  NOT_FOUND = 'NOT_FOUND',
  INVALID_PARAM = 'INVALID_PARAM',
  DEVICE_OFFLINE = 'DEVICE_OFFLINE',
  CONFLICT_SKIPPED = 'CONFLICT_SKIPPED',
  STORAGE_ERROR = 'STORAGE_ERROR',
  UNKNOWN = 'UNKNOWN'
}

/** 设计补充 1：空调模式（PRD 4.3）。 */
export enum ACMode {
  COOL = 'COOL',
  HEAT = 'HEAT',
  FAN = 'FAN',
  DRY = 'DRY',
  AUTO = 'AUTO'
}

/** 设计补充 2：首页当前运行模式（FR-01-07）。 */
export enum RunMode {
  STUDY = 'STUDY',
  SLEEP = 'SLEEP',
  AWAY = 'AWAY',
  RETURN = 'RETURN',
  CUSTOM = 'CUSTOM',
  MANUAL = 'MANUAL'
}

/** 设计补充 3：setParam 的强类型键，替代 PRD 8.1 的 key: string。 */
export enum ParamKey {
  BRIGHTNESS = 'brightness',
  TEMPERATURE = 'temperature',
  MODE = 'mode',
  OPEN_PERCENT = 'openPercent',
  LOCKED = 'locked',
  FAN_SPEED = 'fanSpeed',
  POWER_WATT = 'powerWatt'
}

/** 支撑类型：数据重置粒度（MI-17 / Q-12 三级粒度中前两级）。 */
export enum ResetScope {
  ALL = 'ALL',
  LOGS_ONLY = 'LOGS_ONLY'
}

/** 支撑类型：日志类型（MI-13 LogFilter）。 */
export enum LogType {
  OPERATION = 'OPERATION',
  RULE_EXECUTION = 'RULE_EXECUTION',
  ENVIRONMENT = 'ENVIRONMENT',
  SCENE_SWITCH = 'SCENE_SWITCH'
}
