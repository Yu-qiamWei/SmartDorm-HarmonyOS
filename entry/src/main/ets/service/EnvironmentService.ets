/**
 * 智寓 · 环境服务（MI-07/08 / FR-03）
 *
 * 职责只有三件：
 *   ① `getSnapshot()` 返回当前权威环境快照（读仓储，不自建副本）；
 *   ② `adjust()` 手动调整单传感器读数：先做范围校验（越界拒绝，不钳制静默改值），
 *      通过后写 1 条 `EnvironmentLog(source=MANUAL)` 并提交；
 *   ③ `applySampled()` 接收模拟器产出的新读数：对**每个真正变化**的传感器各写 1 条
 *      `EnvironmentLog(source=SIMULATED)`，提交后触发求值。
 *
 * ★ 阈值判定不在本类（设计 4.8）：条件比较的唯一实现在 `service/RuleMatcher.ets`。
 *   本类只负责「产出读数 → 记日志 → 调用注入的触发函数」。
 * ★ 防环依赖（设计 4.7）：本类**不 import** 规则引擎；求值入口由 T3-05 通过
 *   `setEvaluationTrigger()` 一次性注入。未注入时（阶段三 T3-02 落点时）采样仍可运行，
 *   只是不产生求值。
 *
 * 依据：design/系统架构设计.md 4.1 MI-07/08、4.5、4.7、4.8。
 */
import { IEnvironmentService } from './ServiceContracts';
import { AppDataRepository } from '../store/AppDataRepository';
import { LogService } from './LogService';
import { EnvironmentData } from '../model/EnvironmentData';
import { EnvironmentLog } from '../model/Logs';
import { CommandResult, okResult, noChangeResult, failResult } from '../model/CommandResult';
import { SensorType, EnvSource, ResultCode } from '../model/Enums';
import { validateSensorValue } from '../common/ParamSchema';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';

/** 求值触发点：由 composition root（EntryAbility / ServiceFacade）注入，避免直连规则引擎。 */
export type EvaluationTrigger = (snapshot: EnvironmentData) => Promise<void>;

export class EnvironmentService implements IEnvironmentService {
  private static instance: EnvironmentService = new EnvironmentService();

  private trigger: EvaluationTrigger | undefined = undefined;

  static getInstance(): EnvironmentService {
    return EnvironmentService.instance;
  }

  private constructor() {
  }

  /** MI-07 当前环境快照（权威内存态，只读）。 */
  getSnapshot(): EnvironmentData {
    return AppDataRepository.getInstance().getState().environment;
  }

  /**
   * MI-08 手动调整单个传感器读数。
   * 越界不做静默钳制——直接返回 `INVALID_PARAM` 并说明原因（FR-03-09 的可解释性要求）。
   */
  async adjust(
    sensorType: SensorType,
    value: number | boolean,
    source: EnvSource
  ): Promise<CommandResult<EnvironmentData>> {
    const code: ResultCode = validateSensorValue(sensorType, value);
    if (code !== ResultCode.OK) {
      return failResult<EnvironmentData>(
        code, '传感器取值越界：' + sensorType + '=' + String(value)
      );
    }
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const current: EnvironmentData = repo.getState().environment;
    const before: number | boolean = EnvironmentService.readValue(current, sensorType);
    if (EnvironmentService.sameValue(before, value)) {
      return noChangeResult<EnvironmentData>(current, sensorType + ' 读数未变化');
    }
    const next: EnvironmentData =
      EnvironmentService.withValue(current, sensorType, value, source, TimeUtil.now());
    EnvironmentService.writeLog(sensorType, before, value, source, next.timestamp);
    repo.commitEnvironment(next, 'environment-adjust');
    await this.fireTrigger(next);
    return okResult<EnvironmentData>(next, sensorType + ' 已调整为 ' + String(value));
  }

  /** T3-05 注入求值入口；未注入时采样链路安全降级（不报错、不伪造求值）。 */
  setEvaluationTrigger(trigger: EvaluationTrigger): void {
    this.trigger = trigger;
  }

  /**
   * 模拟采样入口：由 `TimerHost` 回调驱动（TimerHost.tick → EnvironmentSimulator.tick →
   * EnvironmentService.applySampled），写 `EnvironmentLog(source=SIMULATED)` 后触发求值。
   * 只有读数真正变化的传感器才产生日志，避免每 4 秒刷出 5 条同值噪音。
   */
  async applySampled(next: EnvironmentData): Promise<void> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const current: EnvironmentData = repo.getState().environment;
    EnvironmentService.writeDiff(current, next);
    repo.commitEnvironment(next, 'environment-sample');
    await this.fireTrigger(next);
  }

  // ——————————————————————————————————————————————————————
  // 内部
  // ——————————————————————————————————————————————————————

  /** 逐传感器对比，只对变化的传感器写日志。 */
  private static writeDiff(before: EnvironmentData, after: EnvironmentData): void {
    if (before.temperature !== after.temperature) {
      EnvironmentService.writeLog(SensorType.TEMPERATURE, before.temperature, after.temperature,
        after.source, after.timestamp);
    }
    if (before.humidity !== after.humidity) {
      EnvironmentService.writeLog(SensorType.HUMIDITY, before.humidity, after.humidity,
        after.source, after.timestamp);
    }
    if (before.illuminance !== after.illuminance) {
      EnvironmentService.writeLog(SensorType.ILLUMINANCE, before.illuminance, after.illuminance,
        after.source, after.timestamp);
    }
    if (before.airQuality !== after.airQuality) {
      EnvironmentService.writeLog(SensorType.AIR_QUALITY, before.airQuality, after.airQuality,
        after.source, after.timestamp);
    }
    if (before.humanPresence !== after.humanPresence) {
      EnvironmentService.writeLog(SensorType.HUMAN_PRESENCE, before.humanPresence,
        after.humanPresence, after.source, after.timestamp);
    }
  }

  private static writeLog(
    sensorType: SensorType,
    before: number | boolean,
    after: number | boolean,
    source: EnvSource,
    timestamp: number
  ): void {
    const log: EnvironmentLog = {
      id: IdGenerator.log(),
      timestamp: timestamp,
      sensorType: sensorType,
      before: before,
      after: after,
      source: source
    };
    LogService.getInstance().appendEnvironment(log);
  }

  /** 触发求值；触发链异常不得影响采样主流程（阶段三 T3-02 尚无规则引擎，未注入即空操作）。 */
  private async fireTrigger(snapshot: EnvironmentData): Promise<void> {
    const trigger: EvaluationTrigger | undefined = this.trigger;
    if (trigger === undefined) {
      return;
    }
    const task: Promise<void> = trigger(snapshot);
    await task.catch((): void => {
      // 求值异常已在引擎内部按规则粒度捕获；此处兜底防止采样中断。
    });
  }

  private static readValue(env: EnvironmentData, sensorType: SensorType): number | boolean {
    switch (sensorType) {
      case SensorType.TEMPERATURE:
        return env.temperature;
      case SensorType.HUMIDITY:
        return env.humidity;
      case SensorType.ILLUMINANCE:
        return env.illuminance;
      case SensorType.AIR_QUALITY:
        return env.airQuality;
      case SensorType.HUMAN_PRESENCE:
        return env.humanPresence;
      default:
        return 0;
    }
  }

  private static withValue(
    current: EnvironmentData,
    sensorType: SensorType,
    value: number | boolean,
    source: EnvSource,
    now: number
  ): EnvironmentData {
    const next: EnvironmentData = {
      temperature: current.temperature,
      humidity: current.humidity,
      illuminance: current.illuminance,
      airQuality: current.airQuality,
      humanPresence: current.humanPresence,
      timestamp: now,
      source: source
    };
    switch (sensorType) {
      case SensorType.TEMPERATURE:
        if (typeof value === 'number') {
          next.temperature = value;
        }
        break;
      case SensorType.HUMIDITY:
        if (typeof value === 'number') {
          next.humidity = value;
        }
        break;
      case SensorType.ILLUMINANCE:
        if (typeof value === 'number') {
          next.illuminance = value;
        }
        break;
      case SensorType.AIR_QUALITY:
        if (typeof value === 'number') {
          next.airQuality = value;
        }
        break;
      case SensorType.HUMAN_PRESENCE:
        if (typeof value === 'boolean') {
          next.humanPresence = value;
        }
        break;
      default:
        break;
    }
    return next;
  }

  private static sameValue(a: number | boolean, b: number | boolean): boolean {
    return a === b;
  }
}
