/**
 * 智寓 · DM-04 AutomationCondition（FR-04-01/02）
 * 依据：design/系统架构设计.md 3.5 节。
 */
import { SensorType, Operator } from './Enums';

export interface AutomationCondition {
  id: string; // cond_ + UUID
  sensorType: SensorType; // 5 类
  operator: Operator; // GT / LT / IS_TRUE / IS_FALSE
  threshold: number; // 数值型条件必填；布尔条件忽略（置 0）
  unit: string; // '℃' | '%RH' | 'Lux' | 'AQI' | ''
}
