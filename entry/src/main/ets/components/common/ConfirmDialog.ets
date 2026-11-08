/**
 * 智寓 · 二次确认弹窗（核验清单第 32 项 promptAction.showDialog）
 * 用于数据重置（FR-07-03）、删除设备/规则/场景等破坏性操作。
 */
import { promptAction } from '@kit.ArkUI';
import { ThemeTokens } from '../../common/ThemeTokens';
import { ToastHost } from './ToastHost';

export class ConfirmDialog {
  /**
   * 显示二次确认；index=1（确认）时执行 onConfirm，index=0 时执行 onCancel。
   * 弹窗不可用（Previewer 环境）时给出明确 Toast，绝不静默失败。
   */
  static show(
    title: string,
    message: string,
    onConfirm: () => void,
    onCancel?: () => void
  ): void {
    promptAction.showDialog({
      title: title,
      message: message,
      buttons: [
        { text: '取消', color: ThemeTokens.TEXT_SECONDARY },
        { text: '确认', color: ThemeTokens.PRIMARY }
      ]
    }).then((response: promptAction.ShowDialogSuccessResponse): void => {
      if (response.index === 1) {
        onConfirm();
      } else if (onCancel !== undefined) {
        onCancel();
      }
    }).catch((): void => {
      ToastHost.showMessage('弹窗不可用，本次操作已取消');
    });
  }
}

/** ConfirmDialog 的 @Preview 可视载体：按钮触发真实二次确认。 */
@Component
@Preview
export struct ConfirmDialogPreview {
  @State decision: string = '等待确认';

  build() {
    Column() {
      Text(this.decision)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .margin({ bottom: ThemeTokens.SPACE_ITEM_GAP })
      Button('演示二次确认')
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .backgroundColor(ThemeTokens.STATUS_FAULT)
        .borderRadius(ThemeTokens.RADIUS_CONTROL)
        .onClick(() => {
          ConfirmDialog.show(
            '确认演示',
            '这是一个真实的二次确认弹窗，确认后会更新上方文字。',
            (): void => {
              this.decision = '已确认';
              ToastHost.showMessage('确认成功');
            },
            (): void => {
              this.decision = '已取消';
              ToastHost.showMessage('已取消');
            }
          );
        })
    }
    .padding(ThemeTokens.SPACE_CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CARD)
  }
}
