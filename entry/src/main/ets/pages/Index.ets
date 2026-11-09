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

/**
 * @Builder 按引用传递的载体（ArkUI 严格模式要求显式 interface，不能用未类型化对象字面量）。
 *
 * ★ 为什么不能用 `@Builder f(label: string, value: string, unit: string)` 的按值形参：
 *   ArkUI 对 @Builder 的按值参数不建立状态依赖，父组件 @State 变化时 builder 内部
 *   的 Text **不会重绘** —— 这正是「用系统 Back 返回首页后在线/异常数停在旧值、
 *   连『刷新聚合数值』都无效，只有重建实例才正确」的另一条根因。
 *   按引用传递（对象字面量 + 直接放进 @State 变量）才会随状态变化刷新。
 */
interface OverviewCellData {
  label: string;
  value: number;
  unit: string;
}

interface MetricCellData {
  label: string;
  value: number;
  mode: string;
  color: string;
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
  @State tileColumns: number = ThemeTokens.GRID_TILES_PHONE;
  @State cardColumns: number = ThemeTokens.GRID_CARDS_PHONE;

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
      this.applyBreakpoint(result.matches);
    };

  /** 断点 → 列数（唯一换算处）：入口小格子 sm 2 列 / md+ 3 列；设备卡片 sm 单列 / md+ 2 列。 */
  private applyBreakpoint(isTablet: boolean): void {
    this.tileColumns = isTablet ? ThemeTokens.GRID_TILES_TABLET : ThemeTokens.GRID_TILES_PHONE;
    this.cardColumns = isTablet ? ThemeTokens.GRID_CARDS_TABLET : ThemeTokens.GRID_CARDS_PHONE;
  }

  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  /**
   * 保证「订阅 + 断点监听」都处于已注册状态（幂等）。
   *
   * ★ `router.back()` 复用页面栈中的缓存实例，不重走 `aboutToAppear()`；而
   *   `aboutToDisappear()` 在本工程实测会在页面被覆盖时退订。二者叠加会让首页
   *   成为「没有订阅者」的僵尸实例：内存态变了、@State 没变，按刷新按钮也没用。
   *   所有注册入口统一走本方法，`undefined` 才注册，绝不产生重复订阅/重复定时器。
   */
  private ensureSubscriptions(): void {
    if (this.mediaListener === undefined) {
      this.mediaListener = mediaquery.matchMediaSync(ThemeTokens.tabletQuery());
      this.mediaListener.on('change', this.onMediaChange);
      this.applyBreakpoint(this.mediaListener.matches);
    }
    if (this.unsubscribe === undefined) {
      this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    }
  }

  /** 页面（含被 router.back 重新显示的缓存实例）每次显示都重新订阅并按权威内存态刷新。 */
  onPageShow(): void {
    this.ensureSubscriptions();
    this.refresh();
  }

  aboutToAppear(): void {
    this.ensureSubscriptions();
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
  overviewCell(cell: OverviewCellData) {
    Column() {
      Text(cell.label)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
      Text(String(cell.value) + cell.unit)
        .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.PRIMARY)
        .margin({ top: 6 })
        // 387.7vp 下四宫格每格约 58vp 可用宽，"49.7%RH" 在 20fp 会被折成两行
        // （真机 DEV-05，表现为 "50%R" + "H"）。单行 + 自适应缩字号。
        .maxLines(1)
        .minFontSize(11)
        .maxFontSize(20)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .layoutWeight(1)
    .padding(ThemeTokens.SPACE_ITEM_GAP)
    .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CONTROL)
  }

  @Builder
  metricCell(cell: MetricCellData) {
    Column() {
      Text(cell.mode.length > 0 ? this.modeLabel(cell.mode) : String(cell.value))
        .fontSize(ThemeTokens.FONT_TITLE_LARGE)
        .fontWeight(FontWeight.Bold)
        .fontColor(cell.color)
      Text(cell.label)
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
            this.overviewCell({ label: '温度', value: this.temperature, unit: '℃' })
            this.overviewCell({ label: '湿度', value: this.humidity, unit: '%RH' })
            this.overviewCell({ label: '光照', value: this.illuminance, unit: 'Lux' })
            this.overviewCell({ label: '空气质量', value: this.airQuality, unit: 'AQI' })
          }
          .width('100%')
        }

        // —— 聚合统计（FR-01-02 / FR-01-06）——
        SectionCard({ title: '设备与规则', caption: '异常设备数由 FAULT / OFFLINE / 离线真实计数' }) {
          Row() {
            this.metricCell({ label: '在线设备', value: this.onlineCount, mode: '', color: ThemeTokens.STATUS_RUNNING })
            this.metricCell({ label: '异常设备', value: this.abnormalCount, mode: '', color: ThemeTokens.STATUS_FAULT })
            this.metricCell({ label: '规则数', value: this.ruleCount, mode: '', color: ThemeTokens.PRIMARY })
            this.metricCell({ label: '运行模式', value: 0, mode: this.currentMode, color: ThemeTokens.ACCENT })
          }
          .width('100%')
          Row() {
            Button('刷新聚合数值')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
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
          GridRow({ columns: this.tileColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
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
                    .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
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
          GridRow({ columns: this.cardColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
            ForEach(this.devices, (device: Device): void => {
              GridCol({ span: 1 }) {
                DeviceCard({ device: device })
              }
            }, (device: Device): string => DeviceCard.keyOf(device))
          }
          .width('100%')
        }

        Text('数据来自 AppDataRepository 内存态 · 未进行真机运行验证')
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
