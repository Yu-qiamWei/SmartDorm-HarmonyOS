/**
 * 智寓 · 四态状态徽标（FR-01-06 / FR-02-06 / T-03 C5）
 * RUNNING / IDLE / FAULT / OFFLINE 用不同色值与补充说明，FAULT/OFFLINE 明显区分。
 */
import { ThemeTokens } from '../../common/ThemeTokens';

@Component
@Preview
export struct StatusBadge {
  @Prop status: string = 'RUNNING';
  @Prop showHint: boolean = true;

  private hintText(): string {
    if (this.status === 'FAULT') {
      return ' · 需处理';
    }
    if (this.status === 'OFFLINE') {
      return ' · 不可控';
    }
    return '';
  }

  private isAbnormal(): boolean {
    return this.status === 'FAULT' || this.status === 'OFFLINE';
  }

  build() {
    Row() {
      Text(ThemeTokens.statusLabel(this.status) + (this.showHint ? this.hintText() : ''))
        .fontSize(ThemeTokens.FONT_CAPTION)
        .fontColor(ThemeTokens.TEXT_ON_PRIMARY)
        .fontWeight(this.isAbnormal() ? FontWeight.Bold : FontWeight.Normal)
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .backgroundColor(ThemeTokens.statusColor(this.status))
    .borderRadius(ThemeTokens.RADIUS_BADGE)
  }
}
