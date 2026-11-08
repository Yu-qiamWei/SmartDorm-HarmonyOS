/**
 * 智寓 · 环境模拟器（MI-09 / FR-03-07）
 *
 * 两个能力：
 *   ① `nextReading(current, rnd, now)` —— **纯静态函数**：给定当前读数与随机源，
 *      产出下一组**恒在 PRD 4.4 范围内**的合法读数。随机源与时间戳都是入参，
 *      因此可在 Node 侧注入固定随机源做 L2 单测（任务列表 §5.1 第 9 项）。
 *   ② `start/stop/tick` —— 实例侧的最小驱动壳：`start()` 只设置 TimerHost 的开关与间隔，
 *      **不创建第二个定时器**（`TimerHost` 是全工程唯一 `setInterval` 持有者）；
 *      `tick()` 由 TimerHost 回调驱动，推进内部当前读数并返回新快照。
 *
 * ★ 本类不写状态、不写日志：`EnvironmentLog` 由 `EnvironmentService.applySampled()` 写，
 *   保证「日志唯一写入方」不被拆散（设计 4.5）。
 * ★ 波动基准取**权威快照**（`EnvironmentService.getSnapshot()`），不维护私有副本：
 *   否则用户手动调整读数后，下一次采样会把环境拉回模拟器自己的旧值（数据不一致）。
 *   `mock → service` 是合法的向下依赖（mock 为 L5、service 为 L2），且 service 侧
 *   不 import 本类，无环。
 * ★ 钳制复用 `common/ParamSchema.clampToRange()` 与 `Constants.RANGE`，
 *   不在此处复制第二份范围表。
 *
 * 依据：design/系统架构设计.md 4.1 MI-09、4.7，PRD 4.4 传感器范围。
 */
import { EnvironmentData } from '../model/EnvironmentData';
import { EnvSource } from '../model/Enums';
import { RANGE } from '../common/Constants';
import { clampToRange } from '../common/ParamSchema';
import { TimeUtil } from '../common/TimeUtil';
import { EnvironmentService } from '../service/EnvironmentService';
import { TimerHost } from './TimerHost';

export class EnvironmentSimulator {
  private static instance: EnvironmentSimulator = new EnvironmentSimulator();

  private running: boolean = false;

  static getInstance(): EnvironmentSimulator {
    return EnvironmentSimulator.instance;
  }

  private constructor() {
  }

  /** 启动模拟：仅配置并恢复 TimerHost，绝不新建第二个定时器句柄。 */
  start(intervalMs: number): void {
    this.running = true;
    TimerHost.getInstance().configure(true, intervalMs);
    TimerHost.getInstance().resume();
  }

  /** 停止模拟：立即暂停 TimerHost（退后台/关闭模拟开关时调用）。 */
  stop(): void {
    this.running = false;
    TimerHost.getInstance().pause();
  }

  /** 模拟是否处于启动态（诊断用）。 */
  isRunning(): boolean {
    return this.running;
  }

  /** 单步推进：以权威快照为基准生成下一组读数（不维护私有副本，避免与手动调整冲突）。 */
  tick(): EnvironmentData {
    const base: EnvironmentData = EnvironmentService.getInstance().getSnapshot();
    return EnvironmentSimulator.nextReading(
      base, (): number => Math.random(), TimeUtil.now()
    );
  }

  /**
   * 纯函数：下一组合法读数。
   * 波动幅度取「小幅漂移」，四舍五入到 1 位小数；五个字段均经 `clampToRange`
   * 钳制到 PRD 4.4 区间（温度 −10~50、湿度 0~100、光照 0~10000、AQI 0~500），
   * `humanPresence` 恒为布尔（低概率翻转，模拟有人/无人切换）。
   */
  static nextReading(
    current: EnvironmentData,
    rnd: () => number,
    now: number
  ): EnvironmentData {
    const r1: number = rnd();
    const r2: number = rnd();
    const r3: number = rnd();
    const r4: number = rnd();
    const r5: number = rnd();
    const temperature: number = EnvironmentSimulator.round1(
      clampToRange(current.temperature + (r1 - 0.5) * 1.2, RANGE.TEMPERATURE)
    );
    const humidity: number = EnvironmentSimulator.round1(
      clampToRange(current.humidity + (r2 - 0.5) * 4, RANGE.HUMIDITY)
    );
    const illuminance: number = EnvironmentSimulator.round1(
      clampToRange(current.illuminance + (r3 - 0.5) * 120, RANGE.ILLUMINANCE)
    );
    const airQuality: number = EnvironmentSimulator.round1(
      clampToRange(current.airQuality + (r4 - 0.5) * 8, RANGE.AIR_QUALITY)
    );
    const humanPresence: boolean = r5 > 0.85 ? !current.humanPresence : current.humanPresence;
    const next: EnvironmentData = {
      temperature: temperature,
      humidity: humidity,
      illuminance: illuminance,
      airQuality: airQuality,
      humanPresence: humanPresence,
      timestamp: now,
      source: EnvSource.SIMULATED
    };
    return next;
  }

  /** 保留 1 位小数（避免浮点尾巴导致日志/图表出现 25.300000000000004 之类噪音）。 */
  private static round1(value: number): number {
    return Math.round(value * 10) / 10;
  }
}
