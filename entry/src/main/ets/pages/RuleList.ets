/**
 * 智寓 · 自动化规则列表（FR-04 / T-04）
 * 新建 / 编辑 / 启停 / 删除 / 执行记录入口全部真实；空态有真实引导。
 */
import { AutomationRule } from '../model/AutomationRule';
import { AppState } from '../model/AppState';
import { AppDataRepository } from '../store/AppDataRepository';
import { ThemeTokens } from '../common/ThemeTokens';
import { RouteMap } from '../common/RouteMap';
import {
  StateChangeHandler, Unsubscribe, ChangeSet
} from '../common/StateChangeTypes';
import { PageHeader } from '../components/common/PageHeader';
import { SectionCard } from '../components/common/SectionCard';
import { RuleCard } from '../components/rule/RuleCard';
import { EmptyView } from '../components/common/EmptyView';
import { ToastHost } from '../components/common/ToastHost';

@Entry
@Component
struct RuleList {
  @State rules: AutomationRule[] = [];
  @State enabledCount: number = 0;

  private unsubscribe: Unsubscribe | undefined = undefined;
  private onStateChange: StateChangeHandler = (change: ChangeSet): void => {
    this.refresh();
  };

  aboutToAppear(): void {
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
    this.rules = state.rules.slice();
    let enabled: number = 0;
    for (let i = 0; i < state.rules.length; i++) {
      if (state.rules[i].enabled) {
        enabled = enabled + 1;
      }
    }
    this.enabledCount = enabled;
  }

  build() {
    Scroll() {
      Column() {
        PageHeader({
          title: '自动化规则',
          subtitle: '共 ' + this.rules.length + ' 条 · 启用 ' + this.enabledCount + ' 条',
          showBack: true,
          actionLabel: '首页'
        })

        SectionCard({
          title: '规则编排',
          caption: '条件 AND 组合 → 有序动作 → 确定性优先级（FR-04-11）'
        }) {
          Row() {
            Button('新建规则')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
              .backgroundColor(ThemeTokens.PRIMARY)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .onClick(() => {
                RouteMap.push(RouteMap.RULE_EDIT, { mode: 'create' });
              })
            Button('查看执行记录')
              .fontSize(ThemeTokens.FONT_BODY)
              .fontColor(ThemeTokens.PRIMARY)
              .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
              .borderRadius(ThemeTokens.RADIUS_CONTROL)
              .layoutWeight(1)
              .margin({ left: ThemeTokens.SPACE_ITEM_GAP })
              .onClick(() => {
                RouteMap.push(RouteMap.STATISTICS);
              })
          }
          .width('100%')
          Button('查看规则求值报告说明')
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .backgroundColor(ThemeTokens.PAGE_BACKGROUND)
            .borderRadius(ThemeTokens.RADIUS_CONTROL)
            .width('100%')
            .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
            .onClick(() => {
              ToastHost.showMessage(
                '规则引擎真实求值、边沿去重 lastSatisfied 与 WriteGuard 冲突处理将在 ST-03 接入'
              );
            })
        }

        SectionCard({ title: '全部规则', caption: '停用规则不参与求值（FR-04-05）' }) {
          if (this.rules.length === 0) {
            EmptyView({
              message: '暂无自动化规则',
              hint: '规则必须由用户在界面上创建后生效，阶段二不预置演示规则',
              actionLabel: '新建规则',
              onAction: (): void => {
                RouteMap.push(RouteMap.RULE_EDIT, { mode: 'create' });
              }
            })
          } else {
            ForEach(this.rules, (rule: AutomationRule): void => {
              RuleCard({ rule: rule })
                .margin({ bottom: ThemeTokens.SPACE_ITEM_GAP })
            }, (rule: AutomationRule): string => rule.id)
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
