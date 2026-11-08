/**
 * 智寓 · 统一反馈封装（核验清单第 32 项 promptAction.showToast）
 *
 * 所有 Service 契约调用的结果都必须经 showResult() 给出「成功 / 无变更 / 失败原因码」
 * 明确中文反馈（FR-08-01 无装饰性按钮、设计 4.2 UI 反馈列）。
 */
import { promptAction } from '@kit.ArkUI';
import { CommandResult } from '../../model/CommandResult';
import { ResultCode } from '../../model/Enums';
import { messageOf } from '../../common/ResultMessage';
import { ThemeTokens } from '../../common/ThemeTokens';

export class ToastHost {
  /** 直接显示一段中文文本。 */
  static showMessage(message: string): void {
    promptAction.showToast({ message: message, duration: 2000 });
  }

  /** 按 ResultCode 出中文提示，可附加原因后缀（如占位说明 / 参数名）。 */
  static showCode(code: ResultCode, suffix?: string): void {
    const base: string = messageOf(code);
    const message: string = suffix === undefined || suffix.length === 0
      ? base
      : base + '（' + suffix + '）';
    promptAction.showToast({ message: message, duration: 2500 });
  }

  /** 统一展示 CommandResult 的 message（含明确原因码语义）。 */
  static showResult<T>(result: CommandResult<T>): void {
    promptAction.showToast({ message: result.message, duration: 2500 });
  }
}

/**
 * ToastHost 的 @Preview 可视载体（C1）：按钮触发真实 Toast，
 * 并真实更新本组件的 @State 局部状态，不是装饰性按钮。
 */
@Component
@Preview
export struct ToastHostPreview {
  @State lastFeedback: string = '尚未触发反馈';

  build() {
    Column() {
      Text(this.lastFeedback)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .margin({ bottom: ThemeTokens.SPACE_ITEM_GAP })
      Button('触发「无变更」反馈')
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .backgroundColor(ThemeTokens.PRIMARY)
        .borderRadius(ThemeTokens.RADIUS_CONTROL)
        .onClick(() => {
          this.lastFeedback = '已触发 NO_CHANGE 反馈';
          ToastHost.showCode(ResultCode.NO_CHANGE, '阶段二接口占位');
        })
    }
    .padding(ThemeTokens.SPACE_CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CARD)
  }
}
