/**
 * 智寓 · 设备管理列表（FR-02 / T-04 D4）
 * 增删入口、状态徽标、跳详情全部真实；平板断点用 GridRow/GridCol 自适应列数。
 */
import { mediaquery } from '@kit.ArkUI';
import { Device } from '../model/Device';
import { CommandResult } from '../model/CommandResult';
import { DeviceType } from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { ServiceFacade } from '../service/ServiceFacade';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { DeviceCard } from '../components/device/DeviceCard';
import { EmptyView } from '../components/common/EmptyView';
import { ConfirmDialog } from '../components/common/ConfirmDialog';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct DeviceList {
  @State devices: Device[] = [];
  @State selectedType: DeviceType = DeviceType.LIGHT;
  @State gridColumns: number = ThemeTokens.GRID_COLUMNS_PHONE;

  private unsubscribe: Unsubscribe | undefined = undefined;
  private mediaListener: mediaquery.MediaQueryListener | undefined = undefined;
  private typeOptions: DeviceType[] = [
    DeviceType.LIGHT,
    DeviceType.AIR_CONDITIONER,
    DeviceType.CURTAIN,
    DeviceType.DOOR_LOCK,
    DeviceType.FAN,
    DeviceType.SOCKET
  ];
  private typeNames: string[] = ['灯光', '空调', '窗帘', '门锁', '风扇', '插座'];

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
    this.devices = AppDataRepository.getInstance().listDevices();
  }

  private addDevice(): void {
    ServiceFacade.getInstance()
      .addDevice(this.selectedType, '新' + this.selectedType + '设备')
      .then((result: CommandResult<Device>): void => {
        ToastHost.showResult<Device>(result);
      });
  }

  private removeDevice(device: Device): void {
    ConfirmDialog.show('删除设备', '确认删除「' + device.name + '」？', (): void => {
      ServiceFacade.getInstance().removeDevice(device.id)
        .then((result: CommandResult<void>): void => {
          ToastHost.showResult(result);
        });
    });
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '设备管理',
          subtitle: '共 ' + this.devices.length + ' 台设备',
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({ title: '添加模拟设备', caption: '选择类型后点击添加（FR-02-04）' }) {
          GridRow({ columns: this.gridColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
            ForEach(this.typeOptions, (type: DeviceType, index: number): void => {
              GridCol({ span: 1 }) {
                Button(this.typeNames[index])
                  .fontSize(ThemeTokens.FONT_BODY)
                  .fontColor(this.selectedType === type
                    ? ThemeTokens.TEXT_ON_PRIMARY : ThemeTokens.PRIMARY)
                  .backgroundColor(this.selectedType === type
                    ? ThemeTokens.PRIMARY : ThemeTokens.PAGE_BACKGROUND)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .width('100%')
                  .onClick(() => {
                    this.selectedType = type;
                    ToastHost.showMessage('已选择设备类型：' + type);
                  })
              }
            }, (type: DeviceType): string => type)
          }
          .width('100%')
          Button('添加设备（' + this.selectedType + '）')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.ACCENT)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              this.addDevice();
            })
        }

        SectionCard({ title: '全部设备', caption: '点击卡片可进详情；删除前二次确认' }) {
          if (this.devices.length === 0) {
            EmptyView({
              message: '当前没有设备',
              hint: '用上方添加入口创建一台模拟设备',
              actionLabel: '回到首页',
              onAction: (): void => {
                RouteMap.push(RouteMap.INDEX);
              }
            })
          } else {
            GridRow({ columns: this.gridColumns, gutter: ThemeTokens.SPACE_ITEM_GAP }) {
              ForEach(this.devices, (device: Device): void => {
                GridCol({ span: 1 }) {
                  Column() {
                    DeviceCard({ device: device })
                    Button('删除此设备')
                      .fontSize(ThemeTokens.FONT_CAPTION)
                      .fontColor(ThemeTokens.STATUS_FAULT)
                      .backgroundColor(ThemeTokens.WARNING_BACKGROUND)
                      .borderRadius(ThemeTokens.RADIUS_CONTROL)
                      .width('100%')
                      .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
                      .onClick(() => {
                        this.removeDevice(device);
                      })
                  }
                  .width('100%')
                }
              }, (device: Device): string => device.id)
            }
            .width('100%')
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
