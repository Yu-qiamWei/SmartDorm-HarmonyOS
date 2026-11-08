/**
 * 智寓 · 统计聚合服务（FR-06-02/03/05 / Q-03）
 *
 * ★ 零 `@kit.*` 依赖（只依赖 `model/`、`common/TimeUtil`、`common/ThemeTokens`），
 *   因此可被 L2 Node 单测覆盖（任务列表 5.1 第 10 项）。
 *   契约 `IStatisticsService` 刻意放在 `service/StatisticsContract.ets`（同样零 Kit）：
 *   若 import `ServiceContracts`，会经 `mock/MockDataFactory` 拉入 `@kit.ArkTS`，
 *   断掉本类的 L2 可测路径；而 ArkTS 不支持结构化类型，不显式 `implements` 又无法赋给接口。
 *
 * ★ 统计一律为**派生计算**：入参是真实日志数组，出参是图表模型，
 *   不向仓储写回任何聚合结果（避免第二数据源，设计 4.1「四面一致」）。
 * ★ 禁止造点：点数 == 传入日志条数，不插值、不补齐、不硬编码演示数据（FR-06-03）。
 *
 * 依据：design/系统架构设计.md 3.13、4.6（派生指标口径）、PRD FR-06-02/03。
 */
import { EnvironmentLog, OperationLog, RuleExecutionLog } from '../model/Logs';
import {
  ChartPoint, ChartBar, ChartSeries, LineChartModel, BarChartModel
} from '../model/ChartModels';
import { Device } from '../model/Device';
import { DeviceType, RuleExecStatus, SensorType } from '../model/Enums';
import { TimeUtil } from '../common/TimeUtil';
import { ThemeTokens } from '../common/ThemeTokens';
import { IStatisticsService } from './StatisticsContract';

export class StatisticsService implements IStatisticsService {
  private static instance: StatisticsService = new StatisticsService();

  static getInstance(): StatisticsService {
    return StatisticsService.instance;
  }

  private constructor() {
  }

  /**
   * 环境日志 → 折线模型。
   * 先按 `sensorType` 过滤、再按 `timestamp` 升序（只排序自建副本，不改入参顺序）。
   * 空数据集返回 `series: []` 且标题注明 0 条，绝不补点。
   */
  buildLineModel(logs: EnvironmentLog[], sensorType: SensorType): LineChartModel {
    const filtered: EnvironmentLog[] = [];
    for (let i = 0; i < logs.length; i++) {
      if (logs[i].sensorType === sensorType) {
        filtered.push(logs[i]);
      }
    }
    filtered.sort((a: EnvironmentLog, b: EnvironmentLog): number => a.timestamp - b.timestamp);

    const points: ChartPoint[] = [];
    for (let i = 0; i < filtered.length; i++) {
      const log: EnvironmentLog = filtered[i];
      points.push({
        label: TimeUtil.formatShort(log.timestamp),
        value: StatisticsService.numberOf(log.after),
        timestamp: log.timestamp
      });
    }

    const title: string = StatisticsService.sensorLabel(sensorType) + '趋势（' +
      points.length + ' 条真实记录）';
    const model: LineChartModel = {
      title: title,
      unit: StatisticsService.sensorUnit(sensorType),
      series: []
    };
    if (points.length > 0) {
      const series: ChartSeries = {
        seriesName: StatisticsService.sensorLabel(sensorType),
        color: ThemeTokens.PRIMARY,
        points: points
      };
      model.series = [series];
      model.min = StatisticsService.minOf(points);
      model.max = StatisticsService.maxOf(points);
    }
    return model;
  }

  /**
   * 操作日志 → 柱状模型：按 `deviceId` 关联 `Device.type` 分组计数。
   * 分组顺序固定（六类设备枚举序 + 未知设备兜底），保证同样输入必然同样输出。
   * 柱状值之和 == 传入日志条数（可断言，测试用例 D8）。
   */
  buildBarModel(logs: OperationLog[], devices: Device[]): BarChartModel {
    const typeById: Map<string, DeviceType> = new Map<string, DeviceType>();
    for (let i = 0; i < devices.length; i++) {
      typeById.set(devices[i].id, devices[i].type);
    }
    const counts: Map<string, number> = new Map<string, number>();
    for (let i = 0; i < logs.length; i++) {
      const log: OperationLog = logs[i];
      const type: DeviceType | undefined = typeById.get(log.deviceId);
      const key: string = type === undefined ? '未知设备' : StatisticsService.typeLabel(type);
      const prev: number | undefined = counts.get(key);
      counts.set(key, (prev === undefined ? 0 : prev) + 1);
    }

    const bars: ChartBar[] = [];
    const order: DeviceType[] = [
      DeviceType.LIGHT, DeviceType.AIR_CONDITIONER, DeviceType.CURTAIN,
      DeviceType.DOOR_LOCK, DeviceType.FAN, DeviceType.SOCKET
    ];
    for (let i = 0; i < order.length; i++) {
      const key: string = StatisticsService.typeLabel(order[i]);
      const value: number | undefined = counts.get(key);
      if (value !== undefined && value > 0) {
        bars.push({ label: key, value: value });
      }
    }
    const unknown: number | undefined = counts.get('未知设备');
    if (unknown !== undefined && unknown > 0) {
      bars.push({ label: '未知设备', value: unknown });
    }

    const model: BarChartModel = {
      title: '设备操作次数（' + logs.length + ' 条真实记录）',
      unit: '次',
      bars: bars,
      color: ThemeTokens.ACCENT
    };
    return model;
  }

  /** 规则成功率：只看 `SUCCESS`；`PARTIAL` 不计成功；空集为 0（不是 NaN，也不是 1）。 */
  successRate(logs: RuleExecutionLog[]): number {
    if (logs.length === 0) {
      return 0;
    }
    let success: number = 0;
    for (let i = 0; i < logs.length; i++) {
      if (logs[i].status === RuleExecStatus.SUCCESS) {
        success = success + 1;
      }
    }
    return success / logs.length;
  }

  /** 平均执行耗时（ms）：只对真实 `durationMs` 求均值，空集 0。 */
  averageDuration(logs: RuleExecutionLog[]): number {
    if (logs.length === 0) {
      return 0;
    }
    let total: number = 0;
    for (let i = 0; i < logs.length; i++) {
      total = total + logs[i].durationMs;
    }
    return total / logs.length;
  }

  // ——————————————————————————————————————————————————————
  // 内部：标签与数值口径
  // ——————————————————————————————————————————————————————

  /** 传感器读数 → 数值（布尔读数映射 0/1，仅用于绘图，不参与阈值判定）。 */
  private static numberOf(value: number | boolean): number {
    if (typeof value === 'number') {
      return value;
    }
    return value ? 1 : 0;
  }

  private static minOf(points: ChartPoint[]): number {
    let min: number = points[0].value;
    for (let i = 1; i < points.length; i++) {
      if (points[i].value < min) {
        min = points[i].value;
      }
    }
    return min;
  }

  private static maxOf(points: ChartPoint[]): number {
    let max: number = points[0].value;
    for (let i = 1; i < points.length; i++) {
      if (points[i].value > max) {
        max = points[i].value;
      }
    }
    return max;
  }

  private static sensorLabel(sensorType: SensorType): string {
    switch (sensorType) {
      case SensorType.TEMPERATURE:
        return '温度';
      case SensorType.HUMIDITY:
        return '湿度';
      case SensorType.ILLUMINANCE:
        return '光照';
      case SensorType.AIR_QUALITY:
        return '空气质量';
      case SensorType.HUMAN_PRESENCE:
        return '人体存在';
      default:
        return '未知传感器';
    }
  }

  private static sensorUnit(sensorType: SensorType): string {
    switch (sensorType) {
      case SensorType.TEMPERATURE:
        return '℃';
      case SensorType.HUMIDITY:
        return '%RH';
      case SensorType.ILLUMINANCE:
        return 'Lux';
      case SensorType.AIR_QUALITY:
        return 'AQI';
      case SensorType.HUMAN_PRESENCE:
        return '0/1';
      default:
        return '';
    }
  }

  private static typeLabel(type: DeviceType): string {
    switch (type) {
      case DeviceType.LIGHT:
        return '灯光';
      case DeviceType.AIR_CONDITIONER:
        return '空调';
      case DeviceType.CURTAIN:
        return '窗帘';
      case DeviceType.DOOR_LOCK:
        return '门锁';
      case DeviceType.FAN:
        return '风扇';
      case DeviceType.SOCKET:
        return '插座';
      default:
        return '未知设备';
    }
  }
}
