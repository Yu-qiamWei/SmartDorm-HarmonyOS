/**
 * 智寓 · 设备卡片（FR-01-03 / FR-02 / T-03 C4）
 * 状态、参数摘要、进详情、快速开关全部有真实回调；数据来自 AppDataRepository 内存态。
 */
import { Device } from '../../model/Device';
import { CommandResult } from '../../model/CommandResult';
import { DeviceStatus, DeviceType, LogActor } from '../../model/Enums';
import { DeviceParamsFactory } from '../../model/DeviceParams';
import { ThemeTokens } from '../../common/ThemeTokens';
import { RouteMap } from '../../common/RouteMap';
import { ServiceFacade } from '../../service/ServiceFacade';
import { ToastHost } from '../common/ToastHost';
import { StatusBadge } from '../common/StatusBadge';

const PREVIEW_DEVICE: Device = {
  id: 'dev_preview_light',
  name: '智能灯光',
  type: DeviceType.LIGHT,
  powerOn: false,
  params: { kind: DeviceType.LIGHT, brightness: 60 },
  online: true,
  status: DeviceStatus.IDLE,
  locked: false,
  createdAt: 0,
  lastUpdated: 0
};

@Component
@Preview
export struct DeviceCard {
  @Prop device: Device = PREVIEW_DEVICE;
  /** 进详情默认实现：真实单栈跳转并携带 deviceId。 */
  onOpenDetail: (deviceId: string) => void = (deviceId: string): void => {
    RouteMap.push(RouteMap.DEVICE_DETAIL, { deviceId: deviceId });
  };
  /** 快速开关默认实现：调用 MI-02 契约占位并用 Toast 反馈 CommandResult。 */
  onQuickToggle: (deviceId: string, on: boolean) => void =
    (deviceId: string, on: boolean): void => {
      ServiceFacade.getInstance().setPower(deviceId, on, LogActor.USER)
        .then((result: CommandResult<Device>): void => {
          ToastHost.showResult<Device>(result);
        });
    };

  build() {
    Column() {
      Row() {
        Text(this.device.name)
          .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Blank()
        StatusBadge({ status: this.device.status })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(DeviceParamsFactory.describe(this.device.params))
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
      Text('电源：' + (this.device.powerOn ? '开启' : '关闭') +
        '　在线：' + (this.device.online ? '是' : '否'))
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_HINT)
        .margin({ top: 4, bottom: ThemeTokens.SPACE_ITEM_GAP })

      Row() {
        Button('查看详情')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .onClick(() => {
            this.onOpenDetail(this.device.id);
          })
        Button(this.device.powerOn ? '关闭' : '开启')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
          .onClick(() => {
            this.onQuickToggle(this.device.id, !this.device.powerOn);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(ThemeTokens.SPACE_CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
  }
}
