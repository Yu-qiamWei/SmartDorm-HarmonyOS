/**
 * 智寓 · 数据统计与历史（FR-06 / Q-03 / T4-D6）
 *
 * 三张 Canvas 自绘图表，全部接收**真实**数据（无静态图片、无演示数据点）：
 *   ① LineChart   ← buildLineModel(真实 EnvironmentLog[])　　　　　温度历史
 *   ② BarChart    ← buildLiveEnvironmentBarModel(真实当前读数)　　环境实时读数
 *   ③ BarChart    ← buildBarModel(真实 OperationLog[] + Device[])　设备运行统计（按设备类型分组）
 * 无记录时由组件自绘空态文案；禁止预置演示数据。
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
  /** 设备运行统计（按设备类型分组，数据源 = 真实 OperationLog[] + Device[]）。 */
  @State deviceBarModel: BarChartModel = {
    title: '设备操作次数', unit: '次', bars: [], color: ThemeTokens.PRIMARY
  };
  @State successRateValue: number = 0;
  @State operationCount: number = 0;
  @State ruleCount: number = 0;
  @State envCount: number = 0;
  @State sceneCount: number = 0;
  @State chartColumns: number = ThemeTokens.GRID_CHARTS_PHONE;

  private unsubscribe: Unsubscribe | undefined = undefined;
  private mediaListener: mediaquery.MediaQueryListener | undefined = undefined;
  private largeListener: mediaquery.MediaQueryListener | undefined = undefined;
  private tabs: LogTab[] = [
    { label: '操作记录', type: LogType.OPERATION },
    { label: '执行记录', type: LogType.RULE_EXECUTION },
    { label: '环境记录', type: LogType.ENVIRONMENT },
    { label: '场景记录', type: LogType.SCENE_SWITCH }
  ];

  private onMediaChange: (result: mediaquery.MediaQueryResult) => void =
    (result: mediaquery.MediaQueryResult): void => {
      this.applyChartColumns();
    };

  private onLargeChange: (result: mediaquery.MediaQueryResult) => void =
    (result: mediaquery.MediaQueryResult): void => {
      this.applyChartColumns();
    };

  /** 图表列数三档：手机 1 列 / 平板 2 列 / 大屏 3 列（唯一换算处）。 */
  private applyChartColumns(): void {
    const isLarge: boolean = this.largeListener !== undefined && this.largeListener.matches;
    const isTablet: boolean = this.mediaListener !== undefined && this.mediaListener.matches;
    if (isLarge) {
      this.chartColumns = ThemeTokens.GRID_CHARTS_LARGE;
    } else if (isTablet) {
      this.chartColumns = ThemeTokens.GRID_CHARTS_TABLET;
    } else {
      this.chartColumns = ThemeTokens.GRID_CHARTS_PHONE;
    }
  }

  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  aboutToAppear(): void {
    this.mediaListener = mediaquery.matchMediaSync(ThemeTokens.tabletQuery());
    this.largeListener = mediaquery.matchMediaSync(ThemeTokens.largeQuery());
    this.mediaListener.on('change', this.onMediaChange);
    this.largeListener.on('change', this.onLargeChange);
    this.applyChartColumns();
    this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.mediaListener !== undefined) {
      this.mediaListener.off('change', this.onMediaChange);
      this.mediaListener = undefined;
    }
    if (this.largeListener !== undefined) {
      this.largeListener.off('change', this.onLargeChange);
      this.largeListener = undefined;
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
    // 第三张图：按设备类型分组统计真实操作次数（形参 groupBy 仅为兼容旧签名，不参与计算）
    this.deviceBarModel = facade.buildBarModel(state.logs.operations, 'deviceType');
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
          // successRate 返回 0~1 的比值，直接拼接会显示成 "1"（真机 DEV-06）。
          // 统一按百分比展示，保留一位小数。
          Text('规则执行成功率（真实日志派生）：' + (this.successRateValue * 100).toFixed(1) + '%')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        // —— 三张 Canvas 自绘图表（响应式：手机单列 / 平板两列 / 大屏三列）——
        GridRow({ columns: this.chartColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
          GridCol({ span: 1 }) {
            LineChart({ model: this.lineModel })
          }
          GridCol({ span: 1 }) {
            BarChart({ model: this.barModel })
          }
          GridCol({ span: 1 }) {
            BarChart({ model: this.deviceBarModel })
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
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
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
            Text('暂无该类记录（系统不预置演示日志，真实操作后产生）')
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
