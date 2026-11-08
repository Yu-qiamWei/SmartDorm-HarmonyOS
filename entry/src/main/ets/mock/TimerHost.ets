/**
 * 智寓 · TimerHost 定时任务全局单例（MI-10 / FR-03-07 / NFR-04 / 核验清单第 24 项）
 *
 * 唯一 `number` 句柄，register / release / pause / resume / tick 均已实现；
 * 页面只订阅、不注册定时器（SK-01~SK-04，TC-E-08）。
 * ★ 阶段三：`tick()` 真实遍历回调表并驱动业务回调（环境采样链路），
 *   但**仍只有 1 个 setInterval 句柄**——`resume()` 内 `this.handle === -1` 判定保证。
 *   是否运行由 `configure(simulationEnabled, intervalMs)` 决定，取自 `settings`。
 */
import { IdGenerator } from '../common/IdGenerator';
import { DEFAULT_SAMPLE_INTERVAL_MS } from '../common/Constants';

export class TimerHost {
  private static instance: TimerHost = new TimerHost();

  /** 唯一的 setInterval 句柄；-1 表示未运行。 */
  private handle: number = -1;
  private registeredHandle: string = '';
  private callbacks: Map<string, () => void> = new Map<string, () => void>();
  private intervalMs: number = DEFAULT_SAMPLE_INTERVAL_MS;
  private simulationEnabled: boolean = false;
  private paused: boolean = true;
  private ticks: number = 0;

  static getInstance(): TimerHost {
    return TimerHost.instance;
  }

  private constructor() {
  }

  /** 由 EntryAbility 按 `settings` 注入：模拟开关 + 采样间隔（间隔非法时回退默认 4000ms）。 */
  configure(simulationEnabled: boolean, intervalMs: number): void {
    this.simulationEnabled = simulationEnabled;
    this.intervalMs = intervalMs > 0 ? intervalMs : DEFAULT_SAMPLE_INTERVAL_MS;
    if (!this.simulationEnabled) {
      this.pause();
    }
  }

  /** MI-10：重复注册返回同一句柄，绝不为同一回调创建第二个定时器。 */
  register(callback: () => void, intervalMs: number): string {
    if (this.registeredHandle.length > 0) {
      return this.registeredHandle;
    }
    const handleKey: string = IdGenerator.withPrefix('timer');
    this.registeredHandle = handleKey;
    this.callbacks.set(handleKey, callback);
    this.intervalMs = intervalMs > 0 ? intervalMs : DEFAULT_SAMPLE_INTERVAL_MS;
    return handleKey;
  }

  /** MI-10：释放句柄与回调表；onDestroy 必须调用。 */
  release(handle: string): void {
    this.pause();
    if (handle.length > 0) {
      this.callbacks.delete(handle);
    } else {
      this.callbacks.clear();
    }
    this.registeredHandle = '';
    this.ticks = 0;
  }

  /** MI-10：立即 clearInterval，退后台一定调用。 */
  pause(): void {
    if (this.handle !== -1) {
      clearInterval(this.handle);
      this.handle = -1;
    }
    this.paused = true;
  }

  /** MI-10：仅当模拟开关打开且未暂停时创建唯一定时器。 */
  resume(): void {
    if (!this.simulationEnabled || this.paused === false) {
      return;
    }
    this.paused = false;
    if (this.handle === -1) {
      const host: TimerHost = this;
      this.handle = setInterval((): void => {
        host.tick();
      }, this.intervalMs);
    }
  }

  /**
   * 单步 tick：累计计数 + **真实驱动**已注册回调（阶段三 T3-02 接通）。
   * 先对回调表做快照再遍历，避免回调内部 register / release 造成遍历期间集合变动。
   * 定时器唯一性仍由 resume() 保证：全工程只有 1 个 setInterval 句柄（B8）。
   */
  tick(): void {
    this.ticks = this.ticks + 1;
    const snapshot: (() => void)[] = [];
    this.callbacks.forEach((callback: () => void): void => {
      snapshot.push(callback);
    });
    for (let i = 0; i < snapshot.length; i++) {
      snapshot[i]();
    }
  }

  /** 诊断：当前定时器句柄（字符串），未注册时返回空串。 */
  currentHandle(): string {
    return this.registeredHandle;
  }

  /** 诊断：number 句柄是否为 -1（可核查无泄漏）。 */
  isRunning(): boolean {
    return this.handle !== -1;
  }

  /** 诊断：tick 累计次数（未启动采样时恒为 0）。 */
  tickCount(): number {
    return this.ticks;
  }

  /** 诊断：当前注册的回调数量（页面不注册，故应为 0 或 1）。 */
  callbackCount(): number {
    return this.callbacks.size;
  }
}
