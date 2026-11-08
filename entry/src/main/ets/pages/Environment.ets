/**
 * 智寓 · 环境监测（FR-03 / T-04）
 * 5 类传感器卡片、手动调整、模拟变化开关、环境历史、求值报告入口全部真实。
 */
import { EnvironmentData } from '../model/EnvironmentData';
import { AppSettings } from '../model/AppSettings';
import { AppState } from '../model/AppState';
import { EnvironmentLog } from '../model/Logs';
import { CommandResult } from '../model/CommandResult';
import { RuleEvaluationReport } from '../model/Reports';
import { SensorType, EnvSource } from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { TimeUtil } from '../common/TimeUtil';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { ServiceFacade } from '../service/ServiceFacade';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { SensorCard } from '../components/env/SensorCard';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct Environment {
  @State temperature: number = 25;
  @State humidity: number = 50;
  @State illuminance: number = 300;
  @State airQuality: number = 50;
  @State humanPresence: boolean = false;
  @State simulationOn: boolean = true;
  @State logs: EnvironmentLog[] = [];
  @State lastReport: string = '尚未请求求值报告';

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
    const state: AppState = AppDataRepository.getInstance().getState();
    const env: EnvironmentData = state.environment;
    this.temperature = env.temperature;
    this.humidity = env.humidity;
    this.illuminance = env.illuminance;
    this.airQuality = env.airQuality;
    this.humanPresence = env.humanPresence;
    this.simulationOn = state.settings.simulationEnabled;
    this.logs = state.logs.environment.slice();
  }

  private toggleSimulation(): void {
    const settings: AppSettings = AppDataRepository.getInstance().getState().settings;
    const updated: AppSettings = {
      automationEnabled: settings.automationEnabled,
      simulationEnabled: !this.simulationOn,
      sampleIntervalMs: settings.sampleIntervalMs,
      logLimit: settings.logLimit,
      schemaVersion: settings.schemaVersion,
      appVersion: settings.appVersion
    };
    const result: CommandResult<AppSettings> =
      ServiceFacade.getInstance().updateSettings(updated);
    this.simulationOn = !this.simulationOn;
    ToastHost.showResult<AppSettings>(result);
  }

  private requestEvaluation(): void {
    const snapshot: EnvironmentData = AppDataRepository.getInstance().getState().environment;
    ServiceFacade.getInstance().evaluateRules(snapshot)
      .then((report: RuleEvaluationReport): void => {
        this.lastReport = '报告时间 ' + TimeUtil.format(report.evaluatedAt) +
          ' · 触发 ' + report.triggeredRules.length + ' 条 · 新增日志 ' + report.newLogs.length + ' 条';
        ToastHost.showMessage(report.skipReason);
      });
  }

  private manualSample(): void {
    ServiceFacade.getInstance()
      .adjustEnvironment(SensorType.TEMPERATURE, this.temperature, EnvSource.MANUAL)
      .then((result: CommandResult<EnvironmentData>): void => {
        ToastHost.showResult<EnvironmentData>(result);
      });
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '环境监测',
          subtitle: '5 类传感器 · 手动调整与模拟变化',
          showBack: true,
          actionLabel: '首页'
        })

        // —— 顶部实时读数条（与其他页面不同布局）——
        Row() {
          Text(this.temperature + '℃')
            .fontSize(ThemeTokens.FONT_TITLE_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          Blank()
          Text(this.humanPresence ? '有人' : '无人')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          Blank()
          Text('采样 ' + TimeUtil.formatShort(TimeUtil.now()))
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        }
        .width('100%')
        .padding(ThemeTokens.SPACE_CARD_PADDING)
        .backgroundColor(ThemeTokens.PRIMARY)
        .borderRadius(ThemeTokens.RADIUS_CARD)
        .margin({ bottom: ThemeTokens.SPACE_SECTION_GAP })

        SectionCard({ title: '模拟变化与求值', caption: this.lastReport }) {
          Row() {
            Button(this.simulationOn ? '关闭环境模拟' : '开启环境模拟')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(this.simulationOn ? ThemeTokens.ACCENT : ThemeTokens.STATUS_IDLE)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.toggleSimulation();
              })
            Button('手动采样一次')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                this.manualSample();
              })
          }
          .width('100%')
          Button('查看规则求值报告（阶段二占位）')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY_DARK)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              this.requestEvaluation();
            })
        }

        // —— 5 类传感器卡片（真实手动调整，越界返回 INVALID_PARAM）——
        SensorCard({
          sensorType: SensorType.TEMPERATURE,
          label: '温度',
          value: this.temperature,
          unit: '℃',
          minValue: -10,
          maxValue: 50,
          step: 1
        })
        SensorCard({
          sensorType: SensorType.HUMIDITY,
          label: '湿度',
          value: this.humidity,
          unit: '%RH',
          minValue: 0,
          maxValue: 100,
          step: 5
        })
        SensorCard({
          sensorType: SensorType.ILLUMINANCE,
          label: '光照',
          value: this.illuminance,
          unit: 'Lux',
          minValue: 0,
          maxValue: 10000,
          step: 50
        })
        SensorCard({
          sensorType: SensorType.AIR_QUALITY,
          label: '空气质量',
          value: this.airQuality,
          unit: 'AQI',
          minValue: 0,
          maxValue: 500,
          step: 10
        })

        SectionCard({ title: '人体存在', caption: '布尔型传感器（IS_TRUE / IS_FALSE 条件）' }) {
          Row() {
            Text(this.humanPresence ? '检测到有人' : '检测到无人')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .layoutWeight(1)
            Button(this.humanPresence ? '置为无人' : '置为有人')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.PRIMARY)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .onClick(() => {
                ServiceFacade.getInstance()
                  .adjustEnvironment(
                    SensorType.HUMAN_PRESENCE,
                    !this.humanPresence,
                    EnvSource.MANUAL
                  )
                  .then((result: CommandResult<EnvironmentData>): void => {
                    ToastHost.showResult<EnvironmentData>(result);
                  });
              })
          }
          .width('100%')
        }

        SectionCard({ title: '环境历史记录', caption: '来自真实 EnvironmentLog' }) {
          if (this.logs.length === 0) {
            Text('暂无环境变化记录（调整传感器后由 ST-03 写入）')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .width('100%')
          } else {
            ForEach(this.logs, (log: EnvironmentLog): void => {
              Row() {
                Text(TimeUtil.format(log.timestamp))
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .fontColor(ThemeTokens.TEXT_HINT)
                Text(log.sensorType + ' ' + log.before + ' → ' + log.after)
                  .fontSize(ThemeTokens.FONT_BODY)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }, (log: EnvironmentLog): string => log.id)
          }
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
}
