/**
 * 智寓 · 规则卡片（FR-04 / T-03 C4）
 * 条件/动作摘要、优先级、启停、编辑、删除全部有真实回调。
 */
import { AutomationRule } from '../../model/AutomationRule';
import { CommandResult } from '../../model/CommandResult';
import { ConditionLogic } from '../../model/Enums';
import { ThemeTokens } from '../../common/ThemeTokens';
import { RouteMap } from '../../common/RouteMap';
import { ServiceFacade } from '../../service/ServiceFacade';
import { ToastHost } from '../common/ToastHost';
import { ConfirmDialog } from '../common/ConfirmDialog';

const PREVIEW_RULE: AutomationRule = {
  id: 'rule_preview_01',
  name: '预览规则（仅 Previewer 占位）',
  enabled: true,
  logic: ConditionLogic.AND,
  conditions: [],
  actions: [],
  priority: 1,
  lastSatisfied: false,
  lastTriggeredAt: 0,
  executionCount: 0,
  createdAt: 0,
  updatedAt: 0
};

@Component
@Preview
export struct RuleCard {
  @Prop rule: AutomationRule = PREVIEW_RULE;
  /** 启停默认实现：调用 MI-11 契约占位并 Toast 反馈。 */
  onToggle: (ruleId: string, enabled: boolean) => void =
    (ruleId: string, enabled: boolean): void => {
      ServiceFacade.getInstance().toggleRule(ruleId, enabled)
        .then((result: CommandResult<AutomationRule>): void => {
          ToastHost.showResult<AutomationRule>(result);
        });
    };
  /** 编辑默认实现：真实跳转编辑页并携带 mode / ruleId。 */
  onEdit: (ruleId: string) => void = (ruleId: string): void => {
    RouteMap.push(RouteMap.RULE_EDIT, { mode: 'edit', ruleId: ruleId });
  };
  /** 删除默认实现：二次确认 → MI-11 契约占位 → Toast。 */
  onDelete: (ruleId: string) => void = (ruleId: string): void => {
    ConfirmDialog.show('删除规则', '确认删除该规则？删除后不再参与求值。', (): void => {
      ServiceFacade.getInstance().removeRule(ruleId)
        .then((result: CommandResult<void>): void => {
          ToastHost.showResult(result);
        });
    });
  };

  build() {
    Column() {
      Row() {
        Text(this.rule.name)
          .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        Blank()
        Text(this.rule.enabled ? '已启用' : '已停用')
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(this.rule.enabled ? ThemeTokens.STATUS_RUNNING : ThemeTokens.TEXT_HINT)
      }
      .width('100%')

      Text('优先级 ' + this.rule.priority + '　·　条件 ' + this.rule.conditions.length +
        ' 条（' + this.rule.logic + '）　·　动作 ' + this.rule.actions.length + ' 条')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .margin({ top: 6 })
      Text('累计执行 ' + this.rule.executionCount + ' 次')
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_HINT)
        .margin({ top: 4, bottom: ThemeTokens.SPACE_ITEM_GAP })

      Row() {
        Button(this.rule.enabled ? '停用' : '启用')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .onClick(() => {
            this.onToggle(this.rule.id, !this.rule.enabled);
          })
        Button('编辑')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
          .onClick(() => {
            this.onEdit(this.rule.id);
          })
        Button('删除')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.STATUS_FAULT)
          .backgroundColor(ThemeTokens.WARNING_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .layoutWeight(1)
          .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
          .onClick(() => {
            this.onDelete(this.rule.id);
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
