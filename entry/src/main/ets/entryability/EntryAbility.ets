/**
 * 智寓 · 应用入口 UIAbility（Stage 模型 / API 17）—— 阶段四 T4-03 持久化接线版
 *
 * 六钩子与落盘职责：
 *   onCreate             → ① PreferencesStore.init(this.context)（必须先于一切 IO）
 *                          ② AppDataRepository.load()（读盘 + 迁移 + 装内存态）
 *                          ③ ServiceFacade.initialize(this.context)（依赖注入的唯一入口）
 *                          ④ 按 settings 配置 TimerHost + 注册采样回调 + 启停模拟
 *   onWindowStageCreate  → windowStage.loadContent('pages/Index')
 *   onForeground         → TimerHost.resume()（模拟开关关闭时不会真的创建定时器）
 *   onBackground         → TimerHost.pause() + **强制 flush()**（异步车道，退后台必须落盘）
 *   onWindowStageDestroy → TimerHost.pause() + saveNowSync()（同步车道，见下方说明）
 *   onDestroy            → TimerHost.release()（一定调用，B8）+ saveNowSync()
 *
 * 为什么销毁路径用 saveNowSync() 而不是 flush()：
 *   `flush()` 返回 Promise，其 resolve 依赖后续微任务/事件循环推进。`onWindowStageDestroy`
 *   与 `onDestroy` 之后进程可能直接结束，Promise 的回调永远不会被调度到，等于没写。
 *   因此这两条「末日路径」必须走**全同步**的 `saveNowSync()`（内部 `flushNowSync()`）。
 *
 * 初始化顺序为什么不能颠倒：
 *   `AppDataRepository.load()` 内部第一步就是 `PreferencesStore.getInstance().has(KEY_01)`
 *   判首启；`PreferencesStore` 未 `init` 时句柄为空，`has` 走「吞异常 + 返回 false」分支，
 *   会把**已存在数据的老用户误判成首启**，随后 `mark()` 全量落盘覆盖真实数据。
 *   所以 `init` 必须在 `load` 之前，且两者都在 `ServiceFacade.initialize` 之前——门面的注入
 *   链路（如环境服务初始化）会读内存态，内存态必须先就位。
 *
 * 采样链路（设计 4.7）：
 *   TimerHost.tick() → EnvironmentSimulator.tick() → EnvironmentService.applySampled(next)
 *                                                      → 写 EnvironmentLog(SIMULATED)
 *                                                      → 调用**注入的** trigger
 * 本文件是应用入口，**不是**注入点：依赖注入全部由 `ServiceFacade.initialize(this.context)`
 * 一次性完成（导出上下文 / Mock 只读查询 / 求值触发），本类只负责把应用上下文递进去。
 * 因此本文件不 import `RuleEngine`、不 import `ExportService`，`EnvironmentService` 侧
 * 也不 import `RuleEngine`（防环 + 单一注入点）。
 *
 * 依据：design/系统架构设计.md 9.1 第 15/21/22/31 项（均已实测核验）、4.7；
 *       design/阶段四验收契约.md 要求 2（onBackground 与 onDestroy 是两条不同落盘路径）。
 * 需求：NFR-04、FR-03-07、E6（simulationEnabled 控制 TimerHost）、E5（触发链闭环）。
 */
import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppDataRepository } from '../store/AppDataRepository';
import { PreferencesStore } from '../store/PreferencesStore';
import { AppState } from '../model/AppState';
import { CommandResult } from '../model/CommandResult';
import { AppSettings } from '../model/AppSettings';
import { EnvironmentData } from '../model/EnvironmentData';
import { TimerHost } from '../mock/TimerHost';
import { EnvironmentSimulator } from '../mock/EnvironmentSimulator';
import { EnvironmentService } from '../service/EnvironmentService';
import { ServiceFacade } from '../service/ServiceFacade';
import { DEFAULT_SAMPLE_INTERVAL_MS } from '../common/Constants';

export default class EntryAbility extends UIAbility {
  /** 冷启动：开存储 → 载内存态 → 注入依赖 → 配置定时器并启停模拟。顺序不可重排。 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // ① 存储句柄就位。必须先于任何读写，且失败时内部已吞异常并记录诊断（返回 void）
    PreferencesStore.getInstance().init(this.context);
    // ② 读盘 + 三级一致性校验 + schema 迁移 + 装内存态（不抛异常，最差回默认态）
    const state: AppState = AppDataRepository.getInstance().load();
    const settings: AppSettings = state.settings;
    const intervalMs: number =
      settings.sampleIntervalMs > 0 ? settings.sampleIntervalMs : DEFAULT_SAMPLE_INTERVAL_MS;
    // ③ 依赖注入全部由门面完成（导出上下文 / Mock 只读查询 / 求值触发），此处只递上下文
    ServiceFacade.getInstance().initialize(this.context);
    // ④ 采样定时器与模拟器按设置启停
    TimerHost.getInstance().configure(settings.simulationEnabled, intervalMs);
    this.registerSampling(intervalMs);
    const simulator: EnvironmentSimulator = EnvironmentSimulator.getInstance();
    if (settings.simulationEnabled) {
      simulator.start(intervalMs);
    } else {
      simulator.stop();
    }
  }

  /** 窗口创建：加载首页（main_pages.json 首项 pages/Index）。 */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index');
  }

  /** 应用回前台：恢复定时器托管（模拟开关关闭时 resume 内部直接返回）。 */
  onForeground(): void {
    TimerHost.getInstance().resume();
  }

  /**
   * 应用退后台：先暂停定时器，再**强制落盘**。
   *
   * 退后台不等于进程结束，此处走异步 `flush()` 即可（事件循环仍在）。
   * `flush()` 内部对分区失败只记 `STORAGE_ERROR` 诊断，**永不 reject**；仍挂 catch 兜底，
   * 防止未来实现变化导致未处理 rejection 拖垮进程。
   */
  onBackground(): void {
    TimerHost.getInstance().pause();
    const task: Promise<CommandResult<void>> = AppDataRepository.getInstance().flush();
    task.catch((): void => {
      // 落盘失败不影响退后台；诊断已由仓储内部记录（STORAGE_ERROR）。
    });
  }

  /**
   * 窗口销毁：暂停 + **同步**落盘。
   *
   * 此钩子之后进程可能立即结束，异步 Promise 不会再有调度机会，故用 `saveNowSync()`。
   */
  onWindowStageDestroy(): void {
    TimerHost.getInstance().pause();
    AppDataRepository.getInstance().saveNowSync();
  }

  /**
   * Ability 销毁：必须 release() 释放唯一句柄与回调表 + **同步**末次落盘。
   *
   * 顺序：先停定时器（不再产生新数据、不再重入写队列），再同步落盘一次，最后 release。
   */
  onDestroy(): void {
    TimerHost.getInstance().pause();
    AppDataRepository.getInstance().saveNowSync();
    TimerHost.getInstance().release(TimerHost.getInstance().currentHandle());
  }

  /**
   * 注册采样回调（全工程只注册一次；TimerHost.register 对重复调用返回同一句柄）。
   * 回调内不做业务判断，只做「推进模拟 → 交给环境服务」两件事。
   */
  private registerSampling(intervalMs: number): void {
    TimerHost.getInstance().register((): void => {
      const next: EnvironmentData = EnvironmentSimulator.getInstance().tick();
      const task: Promise<void> = EnvironmentService.getInstance().applySampled(next);
      task.catch((): void => {
        // 采样链路自身不抛异常；此兜底仅防止未处理 rejection 影响定时器继续运行。
      });
    }, intervalMs);
  }
}
