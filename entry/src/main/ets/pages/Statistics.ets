/**
 * 智寓 · 数据统计与历史（FR-06 / Q-03 / T-04 D6）
 *
 * 折线图 / 柱状图均为 ArkUI Canvas 自绘组件，接收真实数组：
 *   - LineChart 接收 buildLineModel(真实 EnvironmentLog[])（阶段二为空，组件自绘空态）
 *   - BarChart 接收 buildLiveEnvironmentBarModel(真实 EnvironmentData 当前读数)（5 根真实柱）
 * 禁止静态图片、禁止硬编码演示数据点、禁止预置执行日志。
 */
import { mediaquery } from '@kit.ArkUI';
import { AppState } from '../model/AppState';
import { EnvironmentData } from '../model/EnvironmentData';
import { LineChartModel, BarChartModel } from '../model/ChartModels';
import {
  OperationLog, RuleExecutionLog, EnvironmentLog, SceneSwitchLog
} from '../model/Logs';
import { SensorType, LogType } from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { TimeUtil } from '../common/TimeUtil';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { ServiceFacade } from '../service/ServiceFacade';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { LineChart } from '../components/chart/LineChart';
import { BarChart } from '../components/chart/BarChart';
import { ToastHost } from '../components/common/ToastHost';

interface LogTab {
  label: string;
  type: LogType;
}

@Entry
@Component
struct Statistics {
  @State selectedType: LogType = LogType.OPERATION;
  @State lineModel: LineChartModel = { title: '温度历史', unit: '℃', series: [] };
  @State barModel: BarChartModel = {
    title: '当前环境读数', unit: '读数', bars: [], color: ThemeTokens.ACCENT
  };
  @State successRateValue: number = 0;
  @State operationCount: number = 0;
  @State ruleCount: number = 0;
  @State envCount: number = 0;
  @State sceneCount: number = 0;
  @State chartColumns: number = 1;

  private unsubscribe: Unsubscribe | undefined = undefined;
  private mediaListener: mediaquery.MediaQueryListener | undefined = undefined;
  private tabs: LogTab[] = [
    { label: '操作记录', type: LogType.OPERATION },
    { label: '执行记录', type: LogType.RULE_EXECUTION },
    { label: '环境记录', type: LogType.ENVIRONMENT },
    { label: '场景记录', type: LogType.SCENE_SWITCH }
  ];

  private onMediaChange: (result: mediaquery.MediaQueryResult) => void =
    (result: mediaquery.MediaQueryResult): void => {
      this.chartColumns = result.matches ? 2 : 1;
    };

  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  aboutToAppear(): void {
    this.mediaListener = mediaquery.matchMediaSync(ThemeTokens.tabletQuery());
    this.chartColumns = this.mediaListener.matches ? 2 : 1;
    this.mediaListener.on('change', this.onMediaChange);
    this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.mediaListener !== undefined) {
      this.mediaListener.off('change', this.onMediaChange);
      this.mediaListener = undefined;
    }
    if (this.unsubscribe !== undefined) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private refresh(): void {
    const state: AppState = AppDataRepository.getInstance().getState();
    const facade: ServiceFacade = ServiceFacade.getInstance();
    const env: EnvironmentData = state.environment;
    this.operationCount = state.logs.operations.length;
    this.ruleCount = state.logs.ruleExecutions.length;
    this.envCount = state.logs.environment.length;
    this.sceneCount = state.logs.sceneSwitches.length;
    this.lineModel = facade.buildLineModel(state.logs.environment, SensorType.TEMPERATURE);
    this.barModel = facade.buildLiveEnvironmentBarModel(env);
    this.successRateValue = facade.successRate(state.logs.ruleExecutions);
  }

  /** 按选中类型读取真实日志并转成展示行（避免 UI 直接访问判别联合的非共有字段）。 */
  private selectedRecords(): string[] {
    const state: AppState = AppDataRepository.getInstance().getState();
    const lines: string[] = [];
    if (this.selectedType === LogType.OPERATION) {
      for (let i = 0; i < state.logs.operations.length; i++) {
        const log: OperationLog = state.logs.operations[i];
        lines.push(TimeUtil.format(log.timestamp) + ' · ' + log.action + ' · ' + log.result);
      }
    } else if (this.selectedType === LogType.RULE_EXECUTION) {
      for (let i = 0; i < state.logs.ruleExecutions.length; i++) {
        const log: RuleExecutionLog = state.logs.ruleExecutions[i];
        lines.push(TimeUtil.format(log.timestamp) + ' · ' + log.ruleName + ' · ' + log.status);
      }
    } else if (this.selectedType === LogType.ENVIRONMENT) {
      for (let i = 0; i < state.logs.environment.length; i++) {
        const log: EnvironmentLog = state.logs.environment[i];
        lines.push(TimeUtil.format(log.timestamp) + ' · ' + log.sensorType +
          ' ' + log.before + ' → ' + log.after);
      }
    } else {
      for (let i = 0; i < state.logs.sceneSwitches.length; i++) {
        const log: SceneSwitchLog = state.logs.sceneSwitches[i];
        lines.push(TimeUtil.format(log.timestamp) + ' · ' + log.fromSceneId +
          ' → ' + log.toSceneId);
      }
    }
    return lines;
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '数据统计与历史',
          subtitle: '四类真实记录 · Canvas 自绘图表',
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({ title: '记录总览', caption: '计数来自 AppDataRepository 内存态四类日志' }) {
          GridRow({ columns: 2, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
            GridCol({ span: 1 }) {
              this.statCell('设备操作', this.operationCount)
            }
            GridCol({ span: 1 }) {
              this.statCell('规则执行', this.ruleCount)
            }
            GridCol({ span: 1 }) {
              this.statCell('环境变化', this.envCount)
            }
            GridCol({ span: 1 }) {
              this.statCell('场景切换', this.sceneCount)
            }
          }
          .width('100%')
          Text('规则执行成功率（真实日志派生）：' + this.successRateValue)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        // —— Canvas 自绘图表（响应式：平板两列，手机单列）——
        GridRow({ columns: this.chartColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
          GridCol({ span: 1 }) {
            LineChart({ model: this.lineModel })
          }
          GridCol({ span: 1 }) {
            BarChart({ model: this.barModel })
          }
        }
        .width('100%')
        .margin({ top: ThemeTokens.SPACE_SECTION_GAP })

        SectionCard({ title: '历史记录筛选', caption: '按类型筛选（FR-06-04）' }) {
          GridRow({ columns: 2, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
            ForEach(this.tabs, (tab: LogTab): void => {
              GridCol({ span: 1 }) {
                Button(tab.label)
                  .fontSize(ThemeTokens.FONT_BODY)
                  .fontColor(this.selectedType === tab.type
                    ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.PRIMARY)
                  .backgroundColor(this.selectedType === tab.type
                    ? ThemeTokens.PRIMARY : ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .width('100%')
                  .onClick(() => {
                    this.selectedType = tab.type;
                    ToastHost.showMessage('已筛选：' + tab.label);
                  })
              }
            }, (tab: LogTab): string => tab.type)
          }
          .width('100%')
          Text('当前筛选：' + this.selectedType + ' · 共 ' + this.selectedRecords().length + ' 条')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
          if (this.selectedRecords().length === 0) {
            Text('暂无该类记录（阶段二禁止预置演示日志；ST-03 真实写入后可查）')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .width('100%')
              .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
          } else {
            ForEach(this.selectedRecords(), (line: string, index: number): void => {
              Text(line)
                .fontSize(ThemeTokens.FONT_BODY)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .width('100%')
                .padding({ top: 6, bottom: 6 })
            }, (line: string, index: number): string => 'record_' + index)
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

  @Builder
  statCell(label: string, count: number) {
    Column() {
      Text(String(count))
        .fontSize(ThemeTokens.FONT_TITLE_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.PRIMARY)
      Text(label)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
    }
    .width('100%')
    .padding(ThemeTokens.SPACE_ITEM_GAP)
    .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CONTROL)
  }
}
