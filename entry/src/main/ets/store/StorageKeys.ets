/**
 * 智寓 · KEY-01~10 持久化键常量（设计 8.1 命名规范 / MI-19 / Q-01）
 *
 * 阶段二仅定稿常量与分区枚举；实际读写、序列化、迁移留 ST-04。
 * KEY-10 为 returnSnapshot 独立分区（设计 3.11 / FLOW-04）；SceneSwitchLog
 * 随场景分区 KEY-04 一并序列化，四类日志容量上限仍按 Q-12 分别控制。
 */
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

export class StorageKeys {
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

  /** 十键全量列表，供 ST-04 首次启动落盘与逐区读取遍历。 */
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
    StorageKeys.KEY_10_RETURN_SNAPSHOT
  ];
}
