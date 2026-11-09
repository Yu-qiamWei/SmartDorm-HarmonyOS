/**
 * 智寓 · 设备详情（FR-01-04 / FR-02 / Q-15 / T-04 D5）
 *
 * 参数由 RouteParams 严格解析；全参数、开关与参数控件、历史操作记录、
 * 「模拟/调试」Mock 诊断区（置 RUNNING/IDLE/FAULT/OFFLINE 与 online）全部真实回调。
 */
import { Device } from '../model/Device';
import { OperationLog } from '../model/Logs';
import { CommandResult } from '../model/CommandResult';
import { DeviceParams } from '../model/DeviceParams';
import { DeviceParamsFactory } from '../model/DeviceParams';
import {
  DeviceType, DeviceStatus, ParamKey, LogActor
} from '../model/Enums';
import { AppState } from '../model/AppState';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import { RouteParams } from '../common/RouteParams';
import { TimeUtil } from '../common/TimeUtil';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { ServiceFacade } from '../service/ServiceFacade';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { StatusBadge } from '../components/common/StatusBadge';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct DeviceDetail {
  @State deviceId: string = '';
  @State deviceName: string = '未找到设备';
  @State deviceType: string = '';
  @State status: string = 'IDLE';
  @State online: boolean = false;
  @State powerOn: boolean = false;
  @State paramSummary: string = '';
  @State primaryValue: number = 0;
  @State operationLogs: OperationLog[] = [];
  @State diagnosticNote: string = '诊断操作会调用 Service 契约并给出原因码反馈';

  private unsubscribe: Unsubscribe | undefined = undefined;
  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  aboutToAppear(): void {
    this.deviceId = RouteParams.deviceId();
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
    const device: Device | undefined = AppDataRepository.getInstance().findDevice(this.deviceId);
    if (device === undefined) {
      this.deviceName = '未找到设备（deviceId 为空或已删除）';
      this.deviceType = '';
      this.status = 'OFFLINE';
      this.paramSummary = '';
      this.primaryValue = 0;
      this.operationLogs = [];
      return;
    }
    this.deviceName = device.name;
    this.deviceType = device.type;
    this.status = device.status;
    this.online = device.online;
    this.powerOn = device.powerOn;
    this.paramSummary = DeviceParamsFactory.describe(device.params);
    this.primaryValue = DeviceDetail.readPrimaryValue(device.params);
    const filtered: OperationLog[] = [];
    for (let i = 0; i < state.logs.operations.length; i++) {
      if (state.logs.operations[i].deviceId === this.deviceId) {
        filtered.push(state.logs.operations[i]);
      }
    }
    this.operationLogs = filtered;
  }

  /** 判别联合收窄后读取主参数当前值（AT-04）。 */
  private static readPrimaryValue(params: DeviceParams): number {
    switch (params.kind) {
      case DeviceType.LIGHT:
        return params.brightness;
      case DeviceType.AIR_CONDITIONER:
        return params.temperature;
      case DeviceType.CURTAIN:
        return params.openPercent;
      case DeviceType.FAN:
        return params.fanSpeed;
      case DeviceType.SOCKET:
        return params.powerWatt;
      case DeviceType.DOOR_LOCK:
        return params.locked ? 1 : 0;
      default:
        return 0;
    }
  }

  private primaryKey(): ParamKey {
    switch (this.deviceType) {
      case DeviceType.AIR_CONDITIONER:
        return ParamKey.TEMPERATURE;
      case DeviceType.CURTAIN:
        return ParamKey.OPEN_PERCENT;
      case DeviceType.DOOR_LOCK:
        return ParamKey.LOCKED;
      case DeviceType.FAN:
        return ParamKey.FAN_SPEED;
      case DeviceType.SOCKET:
        return ParamKey.POWER_WATT;
      default:
        return ParamKey.BRIGHTNESS;
    }
  }

  private stepOf(): number {
    switch (this.deviceType) {
      case DeviceType.AIR_CONDITIONER:
        return 1;
      case DeviceType.FAN:
        return 1;
      case DeviceType.SOCKET:
        return 100;
      default:
        return 10;
    }
  }

  private togglePower(): void {
    ServiceFacade.getInstance()
      .setPower(this.deviceId, !this.powerOn, LogActor.USER)
      .then((result: CommandResult<Device>): void => {
        ToastHost.showResult<Device>(result);
      });
  }

  private adjustParam(delta: number): void {
    const key: ParamKey = this.primaryKey();
    const next: number = this.primaryValue + delta;
    ServiceFacade.getInstance()
      .setParam(this.deviceId, key, next, LogActor.USER)
      .then((result: CommandResult<Device>): void => {
        ToastHost.showResult<Device>(result);
      });
  }

  private setLock(locked: boolean): void {
    ServiceFacade.getInstance()
      .setParam(this.deviceId, ParamKey.LOCKED, locked, LogActor.USER)
      .then((result: CommandResult<Device>): void => {
        ToastHost.showResult<Device>(result);
      });
  }

  private diagnoseStatus(status: DeviceStatus): void {
    this.diagnosticNote = '最近一次诊断：' + status;
    ServiceFacade.getInstance()
      .setDeviceStatus(this.deviceId, status, LogActor.SYSTEM)
      .then((result: CommandResult<Device>): void => {
        ToastHost.showResult<Device>(result);
      });
  }

  private diagnoseOnline(online: boolean): void {
    this.diagnosticNote = '最近一次诊断：online=' + online;
    ServiceFacade.getInstance()
      .setOnline(this.deviceId, online, LogActor.SYSTEM)
      .then((result: CommandResult<Device>): void => {
        ToastHost.showResult<Device>(result);
      });
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '设备详情',
          subtitle: this.deviceName,
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({ title: '设备状态', caption: 'deviceId：' + this.deviceId }) {
          Row() {
            Column() {
              Text(this.deviceName)
                .fontSize(ThemeTokens.FONT_TITLE_LARGE)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .width('100%')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('类型 ' + this.deviceType + '　·　' + this.paramSummary)
                .fontSize(ThemeTokens.FONT_BODY)
                .fontColor(ThemeTokens.TEXT_SECONDARY)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 6 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            StatusBadge({ status: this.status })
          }
          .width('100%')
          Text('在线：' + (this.online ? '是' : '否') +
            '　电源：' + (this.powerOn ? '开启' : '关闭') +
            '　主参数：' + this.primaryValue)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
          Button(this.powerOn ? '关闭电源' : '开启电源')
            .fontSize(ThemeTokens.FONT_BODY)
            .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              this.togglePower();
            })
        }

        SectionCard({ title: '参数控制', caption: '按设备类型写入对应 ParamKey（FR-02-03）' }) {
          if (this.deviceType === DeviceType.DOOR_LOCK) {
            Row() {
              Button('上锁')
                .fontSize(ThemeTokens.FONT_BODY)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.PRIMARY)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .layoutWeight(1)
                .onClick(() => {
                  this.setLock(true);
                })
              Button('解锁')
                .fontSize(ThemeTokens.FONT_BODY)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.PRIMARY)
                .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .layoutWeight(1)
                .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
                .onClick(() => {
                  this.setLock(false);
                })
            }
            .width('100%')
          } else {
            Row() {
              Button('−' + this.stepOf())
                .fontSize(ThemeTokens.FONT_BODY)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.PRIMARY)
                .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .layoutWeight(1)
                .onClick(() => {
                  this.adjustParam(-this.stepOf());
                })
              Text(this.primaryKey() + ' = ' + this.primaryValue)
                .fontSize(ThemeTokens.FONT_BODY)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Button('+' + this.stepOf())
                .fontSize(ThemeTokens.FONT_BODY)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.PRIMARY)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .layoutWeight(1)
                .onClick(() => {
                  this.adjustParam(this.stepOf());
                })
            }
            .width('100%')
          }
          Text('非法参数会被 ParamSchema 拒绝并返回 INVALID_PARAM（原子性不写入）')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_HINT)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        // —— Mock 诊断区（Q-15，明确标注「模拟/调试」）——
        SectionCard({
          title: '模拟/调试区（非真实硬件故障）',
          caption: this.diagnosticNote
        }) {
          // 6 个短按钮：sm（约 347vp 内容宽）下双列每格约 167vp，文字与 44vp 热区均充足
          GridRow({ columns: ThemeTokens.GRID_TILES_PHONE, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
            GridCol({ span: 1 }) {
              Button('置 RUNNING')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.STATUS_RUNNING)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .width('100%')
                .onClick(() => {
                  this.diagnoseStatus(DeviceStatus.RUNNING);
                })
            }
            GridCol({ span: 1 }) {
              Button('置 IDLE')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.STATUS_IDLE)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .width('100%')
                .onClick(() => {
                  this.diagnoseStatus(DeviceStatus.IDLE);
                })
            }
            GridCol({ span: 1 }) {
              Button('置 FAULT')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.STATUS_FAULT)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .width('100%')
                .onClick(() => {
                  this.diagnoseStatus(DeviceStatus.FAULT);
                })
            }
            GridCol({ span: 1 }) {
              Button('置 OFFLINE')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                .backgroundColor(ThemeTokens.STATUS_OFFLINE)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .width('100%')
                .onClick(() => {
                  this.diagnoseStatus(DeviceStatus.OFFLINE);
                })
            }
            GridCol({ span: 1 }) {
              Button('置在线')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.PRIMARY)
                .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .width('100%')
                .onClick(() => {
                  this.diagnoseOnline(true);
                })
            }
            GridCol({ span: 1 }) {
              Button('置离线')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                .fontColor(ThemeTokens.STATUS_OFFLINE)
                .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .width('100%')
                .onClick(() => {
                  this.diagnoseOnline(false);
                })
            }
          }
          .width('100%')
        }

        SectionCard({ title: '历史操作记录', caption: '来自真实 OperationLog，按 deviceId 过滤' }) {
          if (this.operationLogs.length === 0) {
            Text('该设备暂无操作记录（系统不预置演示日志，操作后产生）')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
              .width('100%')
            Button('去设备列表')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.PRIMARY)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .width('100%')
              .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                RouteMap.push(RouteMap.DEVICE_LIST);
              })
          } else {
            ForEach(this.operationLogs, (log: OperationLog): void => {
              Row() {
                Text(TimeUtil.format(log.timestamp))
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .fontColor(ThemeTokens.TEXT_HINT)
                Text(log.action + ' · ' + log.result)
                  .fontSize(ThemeTokens.FONT_BODY)
                  .fontColor(ThemeTokens.TEXT_PRIMARY)
                  .layoutWeight(1)
                  .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }, (log: OperationLog): string => log.id)
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
