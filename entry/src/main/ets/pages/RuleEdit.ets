/**
 * 智寓 · 规则创建/编辑（FR-04-01~05 / T-04）
 * 多条件 AND、多动作有序、优先级、目标设备、参数校验、保存/取消全部真实交互；
 * 保存走 Service 契约占位并 Toast 反馈，阶段二明确不真实写入。
 */
import { AutomationRule } from '../model/AutomationRule';
import { AutomationCondition } from '../model/AutomationCondition';
import { AutomationAction } from '../model/AutomationAction';
import { Device } from '../model/Device';
import { CommandResult } from '../model/CommandResult';
import {
  ConditionLogic, SensorType, Operator, DeviceCommand, ResultCode
} from '../model/Enums';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import { RouteParams } from '../common/RouteParams';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import { validateSensorValue } from '../common/ParamSchema';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { Stage2ServiceFacade } from '../service/ServiceContracts';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct RuleEdit {
  @State mode: string = 'create';
  @State ruleName: string = '';
  @State priority: number = 1;
  @State threshold: number = 28;
  @State conditionDrafts: string[] = ['温度 大于 28℃'];
  @State actionDrafts: string[] = ['开启目标设备'];
  @State targetIndex: number = 0;
  @State validationNote: string = '参数校验：待输入';
  @State saveNote: string = '尚未提交';

  private ruleId: string = '';
  private unsubscribe: Unsubscribe | undefined = undefined;
  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    // 页面仅订阅，编辑草稿属于页面局部 @State，不被内存态覆盖（SK-01/02）。
  };

  aboutToAppear(): void {
    this.mode = RouteParams.mode();
    this.ruleId = RouteParams.ruleId();
    this.unsubscribe = AppDataRepository.getInstance().subscribe(this.onStateChange);
    if (this.mode === 'edit') {
      const found: AutomationRule | undefined =
        AppDataRepository.getInstance().findRule(this.ruleId);
      if (found !== undefined) {
        this.ruleName = found.name;
        this.priority = found.priority;
      }
    }
    this.revalidate();
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== undefined) {
      this.unsubscribe();
      this.unsubscribe = undefined;
    }
  }

  private revalidate(): void {
    const code: ResultCode = validateSensorValue(SensorType.TEMPERATURE, this.threshold);
    this.validationNote = code === ResultCode.OK
      ? '参数校验：阈值 ' + this.threshold + '℃ 合法（-10—50）'
      : '参数校验：阈值越界，将被拒绝（INVALID_PARAM）';
  }

  private targetDeviceId(): string {
    const devices: Device[] = AppDataRepository.getInstance().listDevices();
    if (devices.length === 0) {
      return '';
    }
    const index: number = this.targetIndex % devices.length;
    return devices[index].id;
  }

  private targetDeviceName(): string {
    const devices: Device[] = AppDataRepository.getInstance().listDevices();
    if (devices.length === 0) {
      return '无可用设备';
    }
    const index: number = this.targetIndex % devices.length;
    return devices[index].name;
  }

  private buildRule(): AutomationRule {
    const now: number = TimeUtil.now();
    const conditions: AutomationCondition[] = [];
    for (let i = 0; i < this.conditionDrafts.length; i++) {
      const condition: AutomationCondition = {
        id: IdGenerator.condition(),
        sensorType: SensorType.TEMPERATURE,
        operator: Operator.GT,
        threshold: this.threshold,
        unit: '℃'
      };
      conditions.push(condition);
    }
    const actions: AutomationAction[] = [];
    const target: string = this.targetDeviceId();
    for (let i = 0; i < this.actionDrafts.length; i++) {
      const action: AutomationAction = {
        id: IdGenerator.action(),
        targetDeviceId: target,
        command: DeviceCommand.POWER_ON,
        value: 1,
        order: i
      };
      actions.push(action);
    }
    const rule: AutomationRule = {
      id: this.mode === 'edit' && this.ruleId.length > 0 ? this.ruleId : IdGenerator.rule(),
      name: this.ruleName,
      enabled: true,
      logic: ConditionLogic.AND,
      conditions: conditions,
      actions: actions,
      priority: this.priority,
      lastSatisfied: false,
      lastTriggeredAt: 0,
      executionCount: 0,
      createdAt: now,
      updatedAt: now
    };
    return rule;
  }

  private save(): void {
    const rule: AutomationRule = this.buildRule();
    const facade: Stage2ServiceFacade = Stage2ServiceFacade.getInstance();
    const task: Promise<CommandResult<AutomationRule>> = this.mode === 'edit'
      ? facade.updateRule(rule)
      : facade.createRule(rule);
    task.then((result: CommandResult<AutomationRule>): void => {
      ToastHost.showResult<AutomationRule>(result);
      if (result.changed) {
        RouteMap.back();
      } else {
        this.saveNote = '阶段二接口占位：未真实写入，草稿已保留在本页';
      }
    });
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: this.mode === 'edit' ? '编辑规则' : '新建规则',
          subtitle: '条件 AND 组合 · 动作按 order 升序执行',
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({ title: '基本信息', caption: this.validationNote }) {
          TextInput({ placeholder: '请输入规则名称', text: this.ruleName })
            .fontSize(ThemeTokens.FONT_BODY)
            .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .onChange((text: string): void => {
              this.ruleName = text;
            })
          Row() {
            Button('优先级 −')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.priority = Math.max(0, this.priority - 1);
              })
            Text('优先级 ' + this.priority)
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_PRIMARY)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            Button('优先级 +')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.priority = this.priority + 1;
              })
          }
          .width('100%')
          .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
        }

        SectionCard({ title: '触发条件（AND）', caption: '共 ' + this.conditionDrafts.length + ' 条' }) {
          ForEach(this.conditionDrafts, (draft: string, index: number): void => {
            Row() {
              Text('条件 ' + (index + 1) + '：' + draft)
                .fontSize(ThemeTokens.FONT_BODY)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .layoutWeight(1)
              Button('移除')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.STATUS_FAULT)
                .backgroundColor(ThemeTokens.WARNING_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .onClick(() => {
                  const next: string[] = this.conditionDrafts.slice();
                  next.splice(index, 1);
                  this.conditionDrafts = next;
                })
            }
            .width('100%')
            .margin({ bottom: 6 })
          }, (draft: string, index: number): string => 'cond_' + index)
          Row() {
            Button('阈值 −1')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.threshold = this.threshold - 1;
                this.revalidate();
              })
            Button('阈值 +1')
              .fontSize(ThemeTokens.FONT_CAPTION)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                this.threshold = this.threshold + 1;
                this.revalidate();
              })
          }
          .width('100%')
          Button('添加条件（温度大于 ' + this.threshold + '℃）')
            .fontSize(ThemeTokens.FONT_BODY)
            .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
            .backgroundColor(ThemeTokens.PRIMARY)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              this.conditionDrafts = this.conditionDrafts.concat(
                ['温度 大于 ' + this.threshold + '℃']
              );
              this.revalidate();
            })
        }

        SectionCard({ title: '执行动作（有序）', caption: '目标设备：' + this.targetDeviceName() }) {
          ForEach(this.actionDrafts, (draft: string, index: number): void => {
            Row() {
              Text('动作 ' + (index + 1) + '：' + draft)
                .fontSize(ThemeTokens.FONT_BODY)
                .fontColor(ThemeTokens.TEXT_PRIMARY)
                .layoutWeight(1)
              Button('移除')
                .fontSize(ThemeTokens.FONT_CAPTION)
                .fontColor(ThemeTokens.STATUS_FAULT)
                .backgroundColor(ThemeTokens.WARNING_BACKGROUND)
                .borderRadius(ThemeTokens.RADIUS_CONTROL)
                .onClick(() => {
                  const next: string[] = this.actionDrafts.slice();
                  next.splice(index, 1);
                  this.actionDrafts = next;
                })
            }
            .width('100%')
            .margin({ bottom: 6 })
          }, (draft: string, index: number): string => 'act_' + index)
          Row() {
            Button('切换目标设备')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.targetIndex = this.targetIndex + 1;
                ToastHost.showMessage('目标设备已切换为：' + this.targetDeviceName());
              })
            Button('添加动作')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.PRIMARY)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                this.actionDrafts = this.actionDrafts.concat(['开启 ' + this.targetDeviceName()]);
              })
          }
          .width('100%')
        }

        SectionCard({ title: '提交', caption: this.saveNote }) {
          Row() {
            Button('保存规则')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.ACCENT)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                this.save();
              })
            Button('取消返回')
              .fontSize(ThemeTokens.FONT_BODY)
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
