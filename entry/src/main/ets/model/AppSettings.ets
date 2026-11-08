/**
 * 智寓 · DM-11 AppSettings（FR-07 / KEY-05 / Q-12）
 * 依据：design/系统架构设计.md 3.8 节。
 */
export interface AppSettings {
  automationEnabled: boolean; // 自动化总开关，默认 true
  simulationEnabled: boolean; // 环境模拟总开关，默认 true
  sampleIntervalMs: number; // 采样间隔，默认 4000（PRD NFR-05 3—5 秒）
  logLimit: number; // 每类日志基准上限，默认 1000（Q-12）
  schemaVersion: number; // 当前 1
  appVersion: string; // '1.0.0'，与 app.json5 一致，不得虚构
}
