/**
 * 智寓 · DM-06 Scene + DeviceStateSnapshot（FR-05 / KEY-10）
 * 依据：design/系统架构设计.md 3.6 节。
 */
import { SceneType, DeviceStatus } from './Enums';
import { DeviceParams } from './DeviceParams';

export interface DeviceStateSnapshot {
  deviceId: string;
  powerOn: boolean;
  params: DeviceParams;
  locked: boolean;
  online: boolean;
  status: DeviceStatus;
  capturedAt: number; // 快照采集时间
}

export interface Scene {
  id: string; // scn_ + UUID
  name: string;
  type: SceneType; // STUDY / SLEEP / AWAY / RETURN / CUSTOM
  deviceStates: DeviceStateSnapshot[]; // 目标设备状态集合，逐条下发
  isPreset: boolean; // 预置不可删（可编辑）
  returnSnapshot: DeviceStateSnapshot[]; // 离寝前用户预设快照（FR-05-04、KEY-10）
  createdAt: number;
  updatedAt: number;
}
