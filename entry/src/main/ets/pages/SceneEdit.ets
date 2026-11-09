/**
 * 智寓 · 场景目标设备状态编辑（FR-05-05 / T-04）
 * 逐设备目标电源状态可切换（真实 @State），保存走 Service 契约占位并 Toast 反馈。
 */
import { Scene } from '../model/Scene';
import { Device } from '../model/Device';
import { DeviceStateSnapshot } from '../model/Scene';
import { CommandResult } from '../model/CommandResult';
import { DeviceParamsFactory } from '../model/DeviceParams';
import { DeviceStatus, SceneType } from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import { RouteParams } from '../common/RouteParams';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { ServiceFacade } from '../service/ServiceFacade';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct SceneEdit {
  @State mode: string = 'create';
  @State sceneName: string = '';
  @State devices: Device[] = [];
  @State targetPower: boolean[] = [];
  @State saveNote: string = '尚未提交';

  private sceneId: string = '';
  private unsubscribe: Unsubscribe | undefined = undefined;
  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    // 编辑草稿为页面局部状态，订阅仅用于保持生命周期规范（SK-01/02）。
  };

  aboutToAppear(): void {
    this.mode = RouteParams.mode();
    this.sceneId = RouteParams.sceneId();
    this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    this.devices = AppDataRepository.getInstance().listDevices();
    const flags: boolean[] = [];
    for (let i = 0; i < this.devices.length; i++) {
      flags.push(false);
    }
    this.targetPower = flags;
    if (this.mode === 'edit') {
      const found: Scene | undefined = AppDataRepository.getInstance().findScene(this.sceneId);
      if (found !== undefined) {
        this.sceneName = found.name;
        const restored: boolean[] = [];
        for (let i = 0; i < this.devices.length; i++) {
          let value: boolean = false;
          for (let j = 0; j < found.deviceStates.length; j++) {
            if (found.deviceStates[j].deviceId === this.devices[i].id) {
              value = found.deviceStates[j].powerOn;
            }
          }
          restored.push(value);
        }
        this.targetPower = restored;
      }
    }
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== undefined) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private toggleTarget(index: number): void {
    const next: boolean[] = this.targetPower.slice();
    next[index] = !next[index];
    this.targetPower = next;
    ToastHost.showMessage(this.devices[index].name + ' 目标电源：' + (next[index] ? '开' : '关'));
  }

  private buildScene(): Scene {
    const now: number = TimeUtil.now();
    const snapshots: DeviceStateSnapshot[] = [];
    for (let i = 0; i < this.devices.length; i++) {
      const device: Device = this.devices[i];
      const snapshot: DeviceStateSnapshot = {
        deviceId: device.id,
        powerOn: this.targetPower[i],
        params: DeviceParamsFactory.defaults(device.type),
        locked: device.locked,
        online: true,
        status: DeviceStatus.IDLE,
        capturedAt: now
      };
      snapshots.push(snapshot);
    }
    const scene: Scene = {
      id: this.mode === 'edit' && this.sceneId.length > 0 ? this.sceneId : IdGenerator.scene(),
      name: this.sceneName,
      type: SceneType.CUSTOM,
      deviceStates: snapshots,
      isPreset: false,
      returnSnapshot: [],
      createdAt: now,
      updatedAt: now
    };
    return scene;
  }

  private save(): void {
    const facade: ServiceFacade = ServiceFacade.getInstance();
    if (this.mode === 'edit') {
      facade.updateScene(this.buildScene())
        .then((result: CommandResult<Scene>): void => {
          ToastHost.showResult<Scene>(result);
          // 未产生变更（幂等成功或失败）时回显真实原因，不写死「占位未实现」
          // ——与 RuleEdit 的 DEV-02 修复同口径：真实返回码不得被占位文案掩盖。
          this.saveNote = result.changed ? '已保存' : result.message;
        });
      return;
    }
    facade.createScene(this.sceneName)
      .then((result: CommandResult<Scene>): void => {
        ToastHost.showResult<Scene>(result);
        this.saveNote = result.changed ? '已保存' : result.message;
      });
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: this.mode === 'edit' ? '编辑场景' : '新建场景',
          subtitle: '逐设备设定目标状态（FR-05-05）',
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({ title: '场景名称', caption: this.saveNote }) {
          TextInput({ placeholder: '请输入场景名称', text: this.sceneName })
            .fontSize(ThemeTokens.FONT_BODY)
            .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .onChange((text: string): void => {
              this.sceneName = text;
            })
          Button('全部开启 / 全部关闭')
            .fontSize(ThemeTokens.FONT_BODY)
            .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              const next: boolean[] = [];
              let anyOff: boolean = false;
              for (let i = 0; i < this.targetPower.length; i++) {
                if (!this.targetPower[i]) {
                  anyOff = true;
                }
              }
              for (let i = 0; i < this.targetPower.length; i++) {
                next.push(anyOff);
              }
              this.targetPower = next;
              ToastHost.showMessage(anyOff ? '已全部设为开启' : '已全部设为关闭');
            })
        }

        SectionCard({
          title: '目标设备状态',
          caption: '共 ' + this.devices.length + ' 台，点击逐台切换目标电源'
        }) {
          if (this.devices.length === 0) {
            Text('暂无设备可配置')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_SECONDARY)
          } else {
            ForEach(this.devices, (device: Device, index: number): void => {
              Row() {
                Column() {
                  Text(device.name)
                    .fontSize(ThemeTokens.FONT_BODY)
                    .fontColor(ThemeTokens.TEXT_PRIMARY)
                  Text(device.type + ' · ' + device.id)
                    .fontSize(ThemeTokens.FONT_CAPTION)
                    .fontColor(ThemeTokens.TEXT_HINT)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Button(this.targetPower[index] ? '目标：开' : '目标：关')
                  .fontSize(ThemeTokens.FONT_CAPTION)
                  .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
                  .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
                  .backgroundColor(this.targetPower[index]
                    ? ThemeTokens.STATUS_RUNNING : ThemeTokens.STATUS_IDLE)
                  .borderRadius(ThemeTokens.RADIUS_CONTROL)
                  .onClick(() => {
                    this.toggleTarget(index);
                  })
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }, (device: Device): string => device.id)
          }
        }

        SectionCard({ title: '提交' }) {
          Row() {
            Button('保存场景')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.ACCENT)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.save();
              })
            Button('取消返回')
              .fontSize(ThemeTokens.FONT_BODY)
              .constraintSize({ minHeight: ThemeTokens.TOUCH_MIN_HEIGHT })
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                RouteMap.back();
              })
          }
          .width('100%')
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
