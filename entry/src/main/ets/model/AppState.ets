/**
 * 智寓 · AppState 单一数据源顶层结构（MI-15 / FR-08-06 四面一致）
 * 依据：design/系统架构设计.md 3.11 节。
 * 唯一权威副本由 AppDataRepository.state 持有；页面只订阅变更、拿只读渲染快照。
 */
import { Device } from './Device';
import { EnvironmentData } from './EnvironmentData';
import { AutomationRule } from './AutomationRule';
import { Scene, DeviceStateSnapshot } from './Scene';
import { LogBundle } from './Logs';
import { AppSettings } from './AppSettings';
import { RunMode } from './Enums';

export interface AppState {
  schemaVersion: number;
  devices: Device[];
  rules: AutomationRule[];
  scenes: Scene[];
  settings: AppSettings;
  environment: EnvironmentData;
  logs: LogBundle;
  returnSnapshot: DeviceStateSnapshot[]; // KEY-10 独立分区
  currentMode: RunMode; // 首页运行模式标识
  currentSceneId: string; // 空串表示手动/自定义
}
