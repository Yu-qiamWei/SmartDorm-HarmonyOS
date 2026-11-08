/**
 * 智寓 · 应用入口 UIAbility（Stage 模型 / API 17）—— 阶段三 T3-02 采样接线版
 *
 * 六钩子：
 *   onCreate            → 载入内存态 + 按 settings 配置 TimerHost + 注册采样回调 + 启停模拟
 *   onWindowStageCreate → windowStage.loadContent('pages/Index')
 *   onForeground        → TimerHost.resume()（模拟开关关闭时不会真的创建定时器）
 *   onBackground        → TimerHost.pause()（一定调用，避免后台运行与泄漏）
 *   onWindowStageDestroy→ pause + 末次 flush（阶段三仍未真实落盘）
 *   onDestroy           → TimerHost.release()（一定调用，B8）+ 末次 flush
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
 * 依据：design/系统架构设计.md 9.1 第 15/21/22/31 项（均已实测核验）、4.7。
 * 需求：NFR-04、FR-03-07、E6（simulationEnabled 控制 TimerHost）、E5（触发链闭环）。
 */
import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppDataRepository } from '../store/AppDataRepository';
import { AppState } from '../model/AppState';
import { AppSettings } from '../model/AppSettings';
import { EnvironmentData } from '../model/EnvironmentData';
import { TimerHost } from '../mock/TimerHost';
import { EnvironmentSimulator } from '../mock/EnvironmentSimulator';
import { EnvironmentService } from '../service/EnvironmentService';
import { ServiceFacade } from '../service/ServiceFacade';
import { DEFAULT_SAMPLE_INTERVAL_MS } from '../common/Constants';

export default class EntryAbility extends UIAbility {
  /** 冷启动：载入内存态、把上下文交给门面完成注入、按设置配置定时器并启停模拟。 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const state: AppState = AppDataRepository.getInstance().load();
    const settings: AppSettings = state.settings;
    const intervalMs: number =
      settings.sampleIntervalMs > 0 ? settings.sampleIntervalMs : DEFAULT_SAMPLE_INTERVAL_MS;
    // ① 依赖注入全部由门面完成（导出上下文 / Mock 只读查询 / 求值触发），此处只递上下文
    ServiceFacade.getInstance().initialize(this.context);
    // ② 采样定时器与模拟器按设置启停
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

  /** 应用退后台：必须暂停，避免后台运行与定时器泄漏。 */
  onBackground(): void {
    TimerHost.getInstance().pause();
  }

  /** 窗口销毁：暂停 + 末次 flush（阶段四接串行写队列后真实落盘）。 */
  onWindowStageDestroy(): void {
    TimerHost.getInstance().pause();
    AppDataRepository.getInstance().flush();
  }

  /** Ability 销毁：必须 release() 释放唯一句柄与回调表 + 末次 flush。 */
  onDestroy(): void {
    TimerHost.getInstance().release(TimerHost.getInstance().currentHandle());
    AppDataRepository.getInstance().flush();
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
