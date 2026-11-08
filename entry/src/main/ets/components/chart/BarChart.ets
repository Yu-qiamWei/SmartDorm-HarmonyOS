/**
 * 智寓 · Canvas 自绘柱状图（FR-06-02/03 / Q-03 / T-03 C2/C3）
 *
 * ★ 只接收 BarChartModel（ChartBar[]）数据数组；无任何图片资源、无内嵌演示数据点。
 * ★ 仅使用核验清单第 25/26 项的 Canvas 绘图方法；onReady + @Watch 重绘。
 */
import { BarChartModel, ChartBar } from '../../model/ChartModels';
import { ThemeTokens } from '../../common/ThemeTokens';

const PREVIEW_BAR_MODEL: BarChartModel = {
  title: '设备运行统计（0 条真实记录）',
  unit: '次',
  bars: [],
  color: ThemeTokens.PRIMARY
};

@Component
@Preview
export struct BarChart {
  @Prop @Watch('onModelChange') model: BarChartModel = PREVIEW_BAR_MODEL;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  onModelChange(): void {
    if (this.ready) {
      this.draw();
    }
  }

  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.context;
    const w: number = ctx.width > 0 ? ctx.width : 600;
    const h: number = ctx.height > 0 ? ctx.height : 220;
    const padding: number = 36;
    const bars: ChartBar[] = this.model.bars;

    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = ThemeTokens.CARD_BACKGROUND;
    ctx.fillRect(0, 0, w, h);

    // 网格与基线
    ctx.strokeStyle = ThemeTokens.DIVIDER;
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const y: number = padding + ((h - padding * 2) * i) / 4;
      ctx.beginPath();
      ctx.moveTo(padding, y);
      ctx.lineTo(w - padding, y);
      ctx.stroke();
    }
    ctx.strokeStyle = ThemeTokens.TEXT_HINT;
    ctx.beginPath();
    ctx.moveTo(padding, padding);
    ctx.lineTo(padding, h - padding);
    ctx.lineTo(w - padding, h - padding);
    ctx.stroke();

    ctx.font = '14px sans-serif';
    if (bars.length === 0) {
      ctx.fillStyle = ThemeTokens.TEXT_HINT;
      ctx.fillText('暂无真实记录（数据来自 OperationLog / 环境读数）', padding + 12, h / 2);
      return;
    }

    let maxValue: number = 1;
    for (let i = 0; i < bars.length; i++) {
      if (bars[i].value > maxValue) {
        maxValue = bars[i].value;
      }
    }

    const plotW: number = w - padding * 2;
    const plotH: number = h - padding * 2;
    const slot: number = plotW / bars.length;
    const barWidth: number = slot * 0.55;
    const color: string = this.model.color.length > 0 ? this.model.color : ThemeTokens.PRIMARY;

    for (let i = 0; i < bars.length; i++) {
      const value: number = bars[i].value;
      const barHeight: number = (plotH * value) / maxValue;
      const x: number = padding + slot * i + (slot - barWidth) / 2;
      const y: number = h - padding - barHeight;
      ctx.fillStyle = color;
      ctx.fillRect(x, y, barWidth, barHeight);
      ctx.fillStyle = ThemeTokens.TEXT_SECONDARY;
      ctx.font = '12px sans-serif';
      ctx.fillText(bars[i].label, x, h - padding + 18);
      ctx.fillText(String(value), x, y - 6);
    }
  }

  build() {
    Column() {
      Text(this.model.title + '　单位：' + this.model.unit)
        .fontSize(ThemeTokens.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeTokens.TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: ThemeTokens.SPACE_ITEM_GAP })
      Canvas(this.context)
        .width('100%')
        .height(ThemeTokens.CHART_HEIGHT)
        .backgroundColor(ThemeTokens.CARD_BACKGROUND)
        .onReady((): void => {
          this.ready = true;
          this.draw();
        })
    }
    .width('100%')
    .padding(ThemeTokens.SPACE_CARD_PADDING)
    .backgroundColor(ThemeTokens.CARD_BACKGROUND)
    .borderRadius(ThemeTokens.RADIUS_CARD)
    .border({ width: 1, color: ThemeTokens.DIVIDER })
  }
}
