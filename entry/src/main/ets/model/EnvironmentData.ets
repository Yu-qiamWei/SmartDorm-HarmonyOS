/**
 * 智寓 · DM-02 EnvironmentData（FR-03 / PRD 4.4 传感器基线）
 * 依据：design/系统架构设计.md 3.4 节。
 */
import { EnvSource } from './Enums';

export interface EnvironmentData {
  temperature: number; // -10—50 ℃，默认 25
  humidity: number; // 0—100 %RH，默认 50
  illuminance: number; // 0—10000 Lux，默认 300
  airQuality: number; // 0—500 AQI，默认 50
  humanPresence: boolean; // 默认 false
  timestamp: number; // 采样时间，epoch ms UTC
  source: EnvSource; // MANUAL / SIMULATED / INIT
}
