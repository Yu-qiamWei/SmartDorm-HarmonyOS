/**
 * 智寓 · DM-05 AutomationAction（FR-04-01/04）
 * 依据：design/系统架构设计.md 3.5 节。
 */
import { DeviceCommand, ACMode } from './Enums';

export interface AutomationAction {
  id: string; // act_ + UUID
  targetDeviceId: string; // 必须指向存在的设备
  command: DeviceCommand; // 12 类
  value: number | boolean | ACMode; // 依 command 校验类型与范围
  order: number; // 单条规则内动作执行顺序（升序）
}
