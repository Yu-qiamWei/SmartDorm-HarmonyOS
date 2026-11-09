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
import { ThemeTokens } from '../common/ThemeTokens';
import { APP_VERSION, DEFAULT_LOG_LIMIT, DEFAULT_SAMPLE_INTERVAL_MS, SCHEMA_VERSION } from '../common/Constants';
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
  @State flushNote: string = '尚未手动保存';

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
    const settings: AppSettings = AppDataRepository.getInstance().getState().settings;
    this.sampleInterval = settings.sampleIntervalMs;
    this.logLimit = settings.logLimit;
    this.subscriberCount = AppDataRepository.getInstance().subscriberCount();
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
      '将恢复默认设备 / 规则 / 场景 / 设置 / 日志。阶段二为接口占位，不会真实写入。',
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
        this.flushNote = '手动保存请求结果：' + result.code;
        ToastHost.showResult(result);
      });
  }

  private exportState(): void {
    const state: AppState = AppDataRepository.getInstance().getState();
    const result: CommandResult<string> =
      ServiceFacade.getInstance().exportState(state, 'json');
    this.exportNote = '导出请求结果：' + result.code + ' · ' + result.message;
    ToastHost.showResult<string>(result);
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
          Text('· 阶段二：PreferencesStore 实际读写、序列化、schemaVersion 迁移与串行写队列留 ST-04。')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
          Text('· 当前 hdc list targets = [Empty]，已部署模拟器镜像最高 API 12 与 SDK API 17 不匹配；未进行真机运行验证。')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 6 })
          Text('· 所有 Service 调用当前为阶段二接口占位，返回带明确 ResultCode 的安全默认值。')
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
