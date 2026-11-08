/**
 * 智寓 · 统一页头（标题 / 返回 / 右侧操作槽）
 * 依据：设计 2.2.5 #35、T-03 C1/C4。所有可点击控件均绑定真实回调。
 */
import { ThemeTokens } from '../../common/ThemeTokens';
import { RouteMap } from '../../common/RouteMap';

@Component
@Preview
export struct PageHeader {
  @Prop title: string = '智寓';
  @Prop subtitle: string = '宿舍控制中心';
  @Prop showBack: boolean = true;
  @Prop actionLabel: string = '';
  /** 右侧操作槽默认实现：回首页（真实导航，非装饰按钮；首页可覆盖为设置）。 */
  onAction: () => void = (): void => {
    RouteMap.push(RouteMap.INDEX);
  };
  /** 返回默认实现：单栈 back（真实导航）。 */
  onBack: () => void = (): void => {
    RouteMap.back();
  };

  build() {
    Row() {
      if (this.showBack) {
        Button('返回')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.CARD_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .onClick(() => {
            this.onBack();
          })
      }

      Column() {
        Text(this.title)
          .fontSize(ThemeTokens.FONT_TITLE_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(ThemeTokens.FONT_CAPTION)
            .fontColor(ThemeTokens.TEXT_SECONDARY)
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: ThemeTokens.SPACE_ITEM_GAP })

      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
          .backgroundColor(ThemeTokens.PRIMARY)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .onClick(() => {
            this.onAction();
          })
      } else {
        Button('设置')
          .fontSize(ThemeTokens.FONT_BODY)
          .fontColor(ThemeTokens.PRIMARY)
          .backgroundColor(ThemeTokens.CARD_BACKGROUND)
          .borderRadius(ThemeTokens.RADIUS_CONTROL)
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding({
      left: ThemeTokens.SPACE_PAGE_X,
      right: ThemeTokens.SPACE_PAGE_X,
      top: ThemeTokens.SPACE_ITEM_GAP,
      bottom: ThemeTokens.SPACE_ITEM_GAP
    })
    .alignItems(VerticalAlign.Center)
  }
}
