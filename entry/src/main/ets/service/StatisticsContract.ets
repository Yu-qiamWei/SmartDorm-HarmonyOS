/**
 * 智寓 · 统计聚合契约（零 `@kit.*` 依赖 / L2 可测前提）
 *
 * 为什么单独一个文件而不是放在 `service/ServiceContracts.ets`：
 *   ① ArkTS **不支持结构化类型**（`arkts-no-structural-typing`）——类必须显式
 *      `implements` 才能赋给接口。`StatisticsService` 要显式声明 `implements IStatisticsService`，
 *      就必须 import 该接口所在的文件；
 *   ② `ServiceContracts.ets` 传递依赖 `mock/MockDataFactory` → `@kit.ArkTS`，
 *      一旦 `StatisticsService` import 它，Node 侧（阶段五 L2 单测）就无法解析，
 *      `buildLineModel / buildBarModel / successRate / averageDuration` 的可测路径会被直接废掉；
 *   ③ 所以把统计契约抽到本文件（只依赖 `model/`），`ServiceContracts.ets` 再 re-export，
 *      让「显式 implements」与「零 Kit 依赖」同时成立。
 *
 * 这是 T3-04 相对任务列表文件清单的**唯一新增文件**，原因如上，已向主理人报备。
 */
import { EnvironmentLog, OperationLog, RuleExecutionLog } from '../model/Logs';
import { LineChartModel, BarChartModel } from '../model/ChartModels';
import { Device } from '../model/Device';
import { SensorType } from '../model/Enums';

/** MI-13 相关：图表数据聚合（数据必须来自真实日志）。实现：`StatisticsService`。 */
export interface IStatisticsService {
  buildLineModel(logs: EnvironmentLog[], sensorType: SensorType): LineChartModel;
  buildBarModel(logs: OperationLog[], devices: Device[]): BarChartModel;
  successRate(logs: RuleExecutionLog[]): number;
  averageDuration(logs: RuleExecutionLog[]): number;
}
