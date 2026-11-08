/**
 * 智寓 · 应用入口 UIAbility（Stage 模型 / API 17）—— T-05 生命周期集成版
 *
 * 六钩子全部接通契约占位与 TimerHost 骨架（T-01 为空骨架，T-05 完成集成）：
 *   onCreate            → AppDataRepository.load() 占位 + TimerHost.configure(false)
 *   onWindowStageCreate → windowStage.loadContent('pages/Index')
 *   onForeground        → TimerHost.resume()（阶段二默认不启动真实采样）
 *   onBackground        → TimerHost.pause()（一定调用，E1）
 *   onWindowStageDestroy→ pause + 末次 flush 占位
 *   onDestroy           → TimerHost.release()（一定调用，E1）+ 末次 flush 占位
 *
 * 依据：design/系统架构设计.md 第 9.1 节第 15/21/22/31 项（均已实测核验）：
 *   - UIAbility / Want / AbilityConstant 来自 @kit.AbilityKit
 *   - window.WindowStage.loadContent 来自 @kit.ArkUI 导出的 window
 * 需求：NFR-04（生命周期）、FR-03-07（定时器无泄漏）、T-05 E1/E2。
 */
import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppDataRepository } from '../store/AppDataRepository';
import { TimerHost } from '../mock/TimerHost';
import { DEFAULT_SAMPLE_INTERVAL_MS } from '../common/Constants';

export default class EntryAbility extends UIAbility {
  /** 冷启动：载入内存态单一数据源（阶段二占位），配置 TimerHost 不启动真实采样。 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppDataRepository.getInstance().load();
    // 阶段二固定 simulationEnabled=false：不启动任何真实采样定时器（T-05 E2）。
    // TODO(ST-04/ST-03): 改为读取 settings.simulationEnabled 与 sampleIntervalMs，
    // 并在 onCreate 内同步完成 PreferencesStore.init() + load()。
    TimerHost.getInstance().configure(false, DEFAULT_SAMPLE_INTERVAL_MS);
  }

  /** 窗口创建：加载首页（main_pages.json 首项 pages/Index）。 */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index');
  }

  /** 应用回前台：恢复定时器托管（阶段二因开关为 false 不会创建真实定时器）。 */
  onForeground(): void {
    TimerHost.getInstance().resume();
  }

  /** 应用退后台：必须暂停，避免后台运行与定时器泄漏。 */
  onBackground(): void {
    TimerHost.getInstance().pause();
  }

  /** 窗口销毁：暂停 + 末次 flush 占位。 */
  onWindowStageDestroy(): void {
    TimerHost.getInstance().pause();
    // TODO(ST-04): await AppDataRepository.flush() 末次落盘并统一错误处理。
    AppDataRepository.getInstance().flush();
  }

  /** Ability 销毁：必须 release() 释放唯一句柄与回调表 + 末次 flush 占位。 */
  onDestroy(): void {
    TimerHost.getInstance().release(TimerHost.getInstance().currentHandle());
    // TODO(ST-04): await AppDataRepository.flush() 末次落盘并统一错误处理。
    AppDataRepository.getInstance().flush();
  }
}
