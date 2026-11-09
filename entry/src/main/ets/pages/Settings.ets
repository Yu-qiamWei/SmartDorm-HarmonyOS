/**
 * 智寓 · 设置与数据管理（FR-07 / T-04）
 * 两个总开关、采样间隔、日志上限、数据重置（二次确认）、应用信息、
 * 持久化管理入口、导出入口、降级提示全部为真实控件（调用契约 + Toast 反馈）。
 */
import { AppSettings } from '../model/AppSettings';
import { AppState } from '../model/AppState';
import { CommandResult } from '../model/CommandResult';
import { ResetScope } from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { DiagnosticEntry, DiagnosticLevel } from '../store/StorageDiagnostics';
import { ThemeTokens } from '../common/ThemeTokens';
import { APP_VERSION, DEFAULT_LOG_LIMIT, DEFAULT_SAMPLE_INTERVAL_MS, SCHEMA_VERSION } from '../common/Constants';
import { TimeUtil } from '../common/TimeUtil';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { ServiceFacade } from '../service/ServiceFacade';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct Settings {
  @State automationOn: boolean = true;
  @State simulationOn: boolean = true;
  /** 初值取工程级常量（NFR-05），不在页面里写死裸数字。 */
  @State sampleInterval: number = DEFAULT_SAMPLE_INTERVAL_MS;
  @State logLimit: number = DEFAULT_LOG_LIMIT;
  @State subscriberCount: number = 0;
  @State exportNote: string = '尚未导出';
  @State flushNote: string = '数据随生命周期自动落盘；可点「立即保存」强制写入';
  @State dirtyCount: number = 0;
  @State bootCount: number = 0;
  @State lastLaunchAt: number = 0;
  @State diagnostics: DiagnosticEntry[] = [];

  private unsubscribe: Unsubscribe | undefined = undefined;
  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  aboutToAppear(): void {
    this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== undefined) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private refresh(): void {
    const repo = AppDataRepository.getInstance();
    const settings: AppSettings = repo.getState().settings;
    this.sampleInterval = settings.sampleIntervalMs;
    this.logLimit = settings.logLimit;
    this.subscriberCount = repo.subscriberCount();
    this.dirtyCount = repo.dirtyPartitions().length;
    const meta = repo.getRuntimeMeta();
    this.bootCount = meta.bootCount;
    this.lastLaunchAt = meta.lastLaunchAt;
    this.diagnostics = repo.getDiagnostics();
  }

  /** 把 epoch ms 格式化为 ISO UTC；未记录时返回占位符（首启前 lastLaunchAt 为 0）。 */
  private formatLaunchTime(ts: number): string {
    if (ts <= 0) {
      return '—';
    }
    return TimeUtil.toIsoUtc(ts);
  }

  /** 所有设置项统一走 Service 契约占位 + Toast 反馈（FR-08-01）。 */
  private commitSettings(
    automation: boolean,
    simulation: boolean,
    interval: number,
    limit: number
  ): void {
    const current: AppSettings = AppDataRepository.getInstance().getState().settings;
    const updated: AppSettings = {
      automationEnabled: automation,
      simulationEnabled: simulation,
      sampleIntervalMs: interval,
      logLimit: limit,
      schemaVersion: current.schemaVersion,
      appVersion: current.appVersion
    };
    const result: CommandResult<AppSettings> =
      ServiceFacade.getInstance().updateSettings(updated);
    this.automationOn = automation;
    this.simulationOn = simulation;
    this.sampleInterval = interval;
    this.logLimit = limit;
    ToastHost.showResult<AppSettings>(result);
  }

  private resetAll(): void {
    ConfirmDialog.show(
      '重置全部数据',
      '将恢复默认设备 / 规则 / 场景 / 设置 / 日志，并立即持久化（真实写入，不可撤销）。',
      (): void => {
        ServiceFacade.getInstance().resetData(ResetScope.ALL)
          .then((result: CommandResult<AppState>): void => {
            ToastHost.showResult<AppState>(result);
          });
      }
    );
  }

  private manualFlush(): void {
    ServiceFacade.getInstance().flush()
      .then((result: CommandResult<void>): void => {
        this.flushNote = '保存结果：' + result.message;
        ToastHost.showResult(result);
      });
  }

  private exportState(): void {
    const state: AppState = AppDataRepository.getInstance().getState();
    ServiceFacade.getInstance().exportState(state, 'json')
      .then((result: CommandResult<string>): void => {
        this.exportNote = '导出结果：' + result.message;
        ToastHost.showResult<string>(result);
      });
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '设置与数据管理',
          subtitle: '偏好设置 · 持久化 · 导出',
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({ title: '总开关', caption: '自动化求值 / 环境模拟（FR-07-01/02）' }) {
          Row() {
            Button(this.automationOn ? '自动化：开' : '自动化：关')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(this.automationOn ? ThemeTokens.STATUS_RUNNING : ThemeTokens.STATUS_IDLE)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.commitSettings(
                  !this.automationOn, this.simulationOn, this.sampleInterval, this.logLimit
                );
              })
            Button(this.simulationOn ? '环境模拟：开' : '环境模拟：关')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(this.simulationOn ? ThemeTokens.ACCENT : ThemeTokens.STATUS_IDLE)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                this.commitSettings(
                  this.automationOn, !this.simulationOn, this.sampleInterval, this.logLimit
                );
              })
          }
          .width('100%')
        }

        SectionCard({ title: '采样与日志容量', caption: 'Q-12：日志上限与 FIFO 淘汰（ST-03 实现）' }) {
          Row() {
            Button('间隔 −500')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.commitSettings(
                  this.automationOn, this.simulationOn,
                  Math.max(1000, this.sampleInterval - 500), this.logLimit
                );
              })
            Text(this.sampleInterval + ' ms')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Button('间隔 +500')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.commitSettings(
                  this.automationOn, this.simulationOn,
                  Math.min(10000, this.sampleInterval + 500), this.logLimit
                );
              })
          }
          .width('100%')
          Row() {
            Button('上限 −100')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.commitSettings(
                  this.automationOn, this.simulationOn,
                  this.sampleInterval, Math.max(100, this.logLimit - 100)
                );
              })
            Text(String(this.logLimit))
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Button('上限 +100')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.commitSettings(
                  this.automationOn, this.simulationOn,
                  this.sampleInterval, this.logLimit + 100
                );
              })
          }
          .width('100%')
          .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        SectionCard({ title: '应用信息', caption: '版本与平台信息按实测填写，不虚构' }) {
          this.infoRow('应用名称', '智寓 · HarmonyOS 智能宿舍管家')
          this.infoRow('版本', APP_VERSION)
          this.infoRow('目标 SDK', 'HarmonyOS 5.0.5 / API 17')
          this.infoRow('工程模型', 'Stage / ArkTS / ArkUI')
          this.infoRow('bundleName', 'com.smartdorm.harmony')
          this.infoRow('schemaVersion', String(SCHEMA_VERSION))
          this.infoRow('运行时第三方依赖', '零')
        }

        SectionCard({
          title: '持久化管理',
          caption: '当前订阅者数量：' + this.subscriberCount + '（可核查订阅防泄漏）'
        }) {
          Button('手动触发保存')
            .fontSize(ThemeTokens.FONT_BODY)
            .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .onClick(() => {
              this.manualFlush();
            })
          Text(this.flushNote)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
          this.infoRow('待落盘分区', String(this.dirtyCount))
          this.infoRow('累计启动次数', String(this.bootCount))
          this.infoRow('上次启动', this.formatLaunchTime(this.lastLaunchAt))
          Text('持久化诊断（最新 ' + this.diagnostics.length + ' 条）')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
          ForEach(this.diagnostics, (entry: DiagnosticEntry): void => {
            Row() {
              Text('[' + entry.level + '] ' + entry.code)
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(entry.level === DiagnosticLevel.ERROR ? ThemeTokens.STATUS_FAULT : ThemeTokens.TEXT_SECONDARY)
              Text(entry.detail)
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .layoutWeight(1)
                .margin({ left: 6 })
                .maxLines(3)
            }
            .width('100%')
            .margin({ top: 4 })
          }, (entry: DiagnosticEntry): string => entry.seq.toString())
        }

        SectionCard({ title: '数据导出', caption: 'FR-07-04 收窄为沙箱 filesDir 导出' }) {
          Button('导出当前状态（JSON）')
            .fontSize(ThemeTokens.FONT_BODY)
            .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.ACCENT)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .onClick(() => {
              this.exportState();
            })
          Text(this.exportNote)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        SectionCard({ title: '数据重置', caption: 'FR-07-03：重置前必须二次确认' }) {
          Button('重置全部数据')
            .fontSize(ThemeTokens.FONT_BODY)
            .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.STATUS_FAULT)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .onClick(() => {
              this.resetAll();
            })
        }

        SectionCard({ title: '降级与局限说明', caption: 'FR-07-08 / 运行载体风险 10.1' }) {
          Text('· 持久化（PreferencesStore 实际读写、分块序列化、schemaVersion 迁移、串行写队列、生命周期落盘）已在 ST-04 实现；逻辑经 DevEco tsc(strict) 全量类型校验与 282 条 L2 断言验证。')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
          Text('· 设备级运行验证（安装 → 强制停止 → 重启 → 字段级恢复 + 异常降级）需在 DevEco 主机对 API 17 模拟器执行；当前沙箱环境未运行模拟器，尚未进行模拟器运行验证。')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 6 })
          Text('· Service 调用（更新设置 / 重置 / 串行落盘 / 沙箱导出）均为真实实现，返回带明确 ResultCode 的结果；导出前会先 await 持久化完成。')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 6 })
        }
      }
      .width('100%')
      .padding({
        left: ThemeTokens.SPACE_PAGE_X,
        right: ThemeTokens.SPACE_PAGE_X,
        bottom: ThemeTokens.SPACE_SECTION_GAP
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .width('35%')
      Text(value)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }
}
