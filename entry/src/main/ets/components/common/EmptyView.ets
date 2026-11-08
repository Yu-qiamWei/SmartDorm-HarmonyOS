/**
 * 智寓 · 空数据占位（T-03 C1/C4）
 * 引导入口必须真实可跳转，禁止装饰性按钮。默认跳设备管理页。
 */
import { ThemeTokens } from '../../common/ThemeTokens';
import { RouteMap } from '../../common/RouteMap';

@Component
@Preview
export struct EmptyView {
  @Prop message: string = '暂无数据';
  @Prop hint: string = '可从下方入口开始添加内容';
  @Prop actionLabel: string = '去设备管理';
  onAction: () => void = (): void => {
    RouteMap.push(RouteMap.DEVICE_LIST);
  };

  build() {
    Column() {
      Text(this.message)
        .fontSize(ThemeTokens.FONT_TITLE_MEDIUM)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
      Text(this.hint)
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_SECONDARY)
        .margin({ top: 8, bottom: ThemeTokens.SPACE_ITEM_GAP })
      Button(this.actionLabel)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .backgroundColor(ThemeTokens.PRIMARY)
        .borderRadius(ThemeTokens.RADIUS_CONTROL)
        .onClick(() => {
          this.onAction();
        })
    }
    .width('100%')
    .padding({
      top: ThemeTokens.SPACE_SECTION_GAP,
      bottom: ThemeTokens.SPACE_SECTION_GAP
    })
    .alignItems(HorizontalAlign.Center)
  }
}
