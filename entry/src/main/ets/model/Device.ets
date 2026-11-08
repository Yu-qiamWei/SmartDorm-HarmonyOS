/**
 * 智寓 · DM-01 Device（FR-02 / FR-01-03）
 * 依据：design/系统架构设计.md 3.3 节。
 */
import { DeviceType, DeviceStatus } from './Enums';
import { DeviceParams } from './DeviceParams';

export interface Device {
  id: string; // dev_ + util.generateRandomUUID()
  name: string; // 非空
  type: DeviceType; // 6 类
  powerOn: boolean; // 门锁语义以 locked 为准，仍保留一致性字段
  params: DeviceParams; // 判别联合；params.kind 必须与 type 一致
  online: boolean; // Mock 可置 false，支撑首页「异常设备数」
  status: DeviceStatus; // RUNNING / IDLE / FAULT / OFFLINE
  locked: boolean; // 仅门锁有效
  createdAt: number; // epoch ms UTC
  lastUpdated: number; // epoch ms UTC
}

/** DM-01 辅助类型：四态徽标的展示元数据（供 StatusBadge / DeviceCard 渲染）。 */
export interface DeviceStatusView {
  status: DeviceStatus;
  label: string;
  color: string;
  background: string;
}
