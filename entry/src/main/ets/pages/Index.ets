/**
 * 智寓 · 首页控制中心（FR-01 / FR-01-08 / T-04 D4）
 *
 * 数据全部来自 AppDataRepository 内存态 AppState；页面只订阅变更、拿只读快照。
 * 六模块入口全部真实跳转，设备卡片各自独立状态，无装饰性按钮。
 * 平板适配：mediaquery.matchMediaSync + GridRow/GridCol 断点切列（核验清单第 34 项）。
 */
import { mediaquery } from '@kit.ArkUI';
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { DeviceStatus } from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { DeviceCard } from '../components/device/DeviceCard';
import { ToastHost } from '../components/common/ToastHost';

interface ModuleEntry {
  label: string;
  url: string;
  caption: string;
}

@Entry
@Component
struct Index {
  @State devices: Device[] = [];
  @State temperature: number = 0;
  @State humidity: number = 0;
  @State illuminance: number = 0;
  @State airQuality: number = 0;
  @State onlineCount: number = 0;
  @State abnormalCount: number = 0;
  @State ruleCount: number = 0;
  @State currentMode: string = 'MANUAL';
  @State gridColumns: number = ThemeTokens.GRID_COLUMNS_PHONE;

  private unsubscribe: Unsubscribe | undefined = undefined;
  private mediaListener: mediaquery.MediaQueryListener | undefined = undefined;
  private moduleEntries: ModuleEntry[] = [
    { label: '设备管理', url: RouteMap.DEVICE_LIST, caption: '6 类设备' },
    { label: '环境监测', url: RouteMap.ENVIRONMENT, caption: '5 类传感器' },
    { label: '自动化规则', url: RouteMap.RULE_LIST, caption: '条件与动作' },
    { label: '场景模式', url: RouteMap.SCENE_LIST, caption: '一键切换' },
    { label: '数据统计', url: RouteMap.STATISTICS, caption: '真实图表' },
    { label: '设置', url: RouteMap.SETTINGS, caption: '数据与导出' }
  ];

  private onMediaChange: (result: mediaquery.MediaQueryResult) => void =
    (result: mediaquery.MediaQueryResult): void => {
      this.gridColumns = result.matches
        ? ThemeTokens.GRID_COLUMNS_TABLET
        : ThemeTokens.GRID_COLUMNS_PHONE;
    };

  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  aboutToAppear(): void {
    this.mediaListener = mediaquery.matchMediaSync(ThemeTokens.tabletQuery());
    this.gridColumns = this.mediaListener.matches
      ? ThemeTokens.GRID_COLUMNS_TABLET
      : ThemeTokens.GRID_COLUMNS_PHONE;
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
    this.devices = state.devices.slice();
    this.temperature = state.environment.temperature;
    this.humidity = state.environment.humidity;
    this.illuminance = state.environment.illuminance;
    this.airQuality = state.environment.airQuality;
    this.ruleCount = state.rules.length;
    this.currentMode = state.currentMode;
    let online: number = 0;
    let abnormal: number = 0;
    for (let i = 0; i < state.devices.length; i++) {
      const device: Device = state.devices[i];
      if (device.online) {
        online = online + 1;
      }
      if (device.status === DeviceStatus.FAULT || device.status === DeviceStatus.OFFLINE ||
        !device.online) {
        abnormal = abnormal + 1;
      }
    }
    this.onlineCount = online;
    this.abnormalCount = abnormal;
  }

  private modeLabel(mode: string): string {
    switch (mode) {
      case 'STUDY':
        return '学习';
      case 'SLEEP':
        return '睡眠';
      case 'AWAY':
        return '离寝';
      case 'RETURN':
        return '回寝';
      case 'CUSTOM':
        return '自定义';
      default:
        return '手动';
    }
  }

  @Builder
  overviewCell(label: string, value: string, unit: string) {
    Column() {
      Text(label)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
      Text(value + unit)
        .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.PRIMARY)
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .padding(ThemeTokens.SPACE_ITEM_GAP)
    .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CONTROL)
  }

  @Builder
  metricCell(label: string, value: string, color: string) {
    Column() {
      Text(value)
        .fontSize(ThemeTokens.FONT_TITLE_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      Text(label)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '智寓 · 宿舍控制中心',
          subtitle: 'HarmonyOS 智能宿舍管家 · 首页',
          showBack: false,
          actionLabel: '设置',
          onAction: (): void => {
            RouteMap.push(RouteMap.SETTINGS);
          }
        })

        // —— 环境概览 4 项（FR-01-01）——
        SectionCard({ title: '环境概览', caption: '数据来自 EnvironmentData 实时内存态' }) {
          Row() {
            this.overviewCell('温度', String(this.temperature), '℃')
            this.overviewCell('湿度', String(this.humidity), '%RH')
            this.overviewCell('光照', String(this.illuminance), 'Lux')
            this.overviewCell('空气质量', String(this.airQuality), 'AQI')
          }
          .width('100%')
        }

        // —— 聚合统计（FR-01-02 / FR-01-06）——
        SectionCard({ title: '设备与规则', caption: '异常设备数由 FAULT / OFFLINE / 离线真实计数' }) {
          Row() {
            this.metricCell('在线设备', String(this.onlineCount), ThemeTokens.STATUS_RUNNING)
            this.metricCell('异常设备', String(this.abnormalCount), ThemeTokens.STATUS_FAULT)
            this.metricCell('规则数', String(this.ruleCount), ThemeTokens.PRIMARY)
            this.metricCell('运行模式', this.modeLabel(this.currentMode), ThemeTokens.ACCENT)
          }
          .width('100%')
          Row() {
            Button('刷新聚合数值')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                AppDataRepository.getInstance().notify('首页手动刷新', ['devices', 'environment']);
                ToastHost.showMessage('已按当前内存态重新计算聚合数值');
              })
          }
          .width('100%')
          .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        // —— 六模块入口（FR-01-08，全部真实跳转）——
        SectionCard({ title: '功能入口', caption: '六个模块全部可访问，无装饰性入口' }) {
          GridRow({ columns: this.gridColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
            ForEach(this.moduleEntries, (entry: ModuleEntry): void => {
              GridCol({ span: 1 }) {
                Column() {
                  Text(entry.label)
                    .fontSize(ThemeTokens.FONT_BODY)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeTokens.TEXT_PRIMARY)
                  Text(entry.caption)
                    .fontSize(ThemeTokens.FONT_CAPTION)
                    .fontColor(ThemeTokens.TEXT_SECONDARY)
                    .margin({ top: 4, bottom: ThemeTokens.SPACE_ITEM_GAP })
                  Button('进入')
                    .fontSize(ThemeTokens.FONT_CAPTION)
                    .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                    .backgroundColor(ThemeTokens.PRIMARY)
                    .borderRadius(ThemeTokens.RADIUS_CONTROL)
                    .width('100%')
                    .onClick(() => {
                      RouteMap.push(entry.url);
                    })
                }
                .width('100%')
                .padding(ThemeTokens.SPACE_ITEM_GAP)
                .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
              }
            }, (entry: ModuleEntry): string => entry.url)
          }
          .width('100%')
        }

        // —— ≥6 类设备卡片（FR-01-03，GridRow/GridCol 响应式列数）——
        SectionCard({
          title: '设备状态',
          caption: '共 ' + this.devices.length + ' 台设备，卡片可进详情 / 快速开关'
        }) {
          GridRow({ columns: this.gridColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
            ForEach(this.devices, (device: Device): void => {
              GridCol({ span: 1 }) {
                DeviceCard({ device: device })
              }
            }, (device: Device): string => device.id)
          }
          .width('100%')
        }

        Text('阶段二工程骨架 · 业务逻辑将在 ST-03 接入 · 未进行真机运行验证')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_HINT)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: ThemeTokens.SPACE_SECTION_GAP, bottom: ThemeTokens.SPACE_SECTION_GAP })
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
