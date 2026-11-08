/**
 * 智寓 · 统一圆角卡片容器（NFR-10 / T-03 C1）
 * 颜色、圆角、内边距全部取自 ThemeTokens，禁止散落硬编码色值。
 */
import { ThemeTokens } from '../../common/ThemeTokens';

@Component
@Preview
export struct SectionCard {
  @Prop title: string = '卡片标题';
  @Prop caption: string = '';

  @Builder
  defaultBody(): void {
    Text('卡片内容区（默认占位，调用方可通过 body 传入任意布局）')
      .fontSize(ThemeTokens.FONT_BODY)
      .fontColor(ThemeTokens.TEXT_SECONDARY)
  }

  /** BuilderParam 带默认实现，保证 @Preview 可独立构造。 */
  @BuilderParam body: () => void = this.defaultBody;

  build() {
    Column() {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeTokens.TEXT_PRIMARY)
          .width('100%')
      }
      if (this.caption.length > 0) {
        Text(this.caption)
          .fontSize(ThemeTokens.FONT_CAPTION)
          .fontColor(ThemeTokens.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 4, bottom: ThemeTokens.SPACE_ITEM_GAP })
      }
      Column() {
        this.body()
      }
      .width('100%')
      .margin({ top: ThemeTokens.SPACE_ITEM_GAP })
    }
    .width('100%')
    .padding(ThemeTokens.SPACE_CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .shadow({
      radius: 12,
      color: ThemeTokens.DIVIDER,
      offsetX: 0,
      offsetY: 4
    })
  }
}
