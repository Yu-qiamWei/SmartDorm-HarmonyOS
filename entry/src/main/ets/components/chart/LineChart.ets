/**
 * 智寓 · Canvas 自绘折线图（FR-06-02/03 / Q-03 / T-03 C2/C3）
 *
 * ★ 只接收 LineChartModel（ChartPoint[] / ChartSeries[]）数据数组；
 *   组件内不引用任何图片资源或媒体资源、无内嵌预置数据点。
 * ★ 绘图仅使用已核验 API（核验清单第 25/26 项）：
 *   Canvas / CanvasRenderingContext2D / RenderingContextSettings / onReady /
 *   clearRect / beginPath / moveTo / lineTo / stroke / fillRect / fillText /
 *   fillStyle / strokeStyle / lineWidth / font。
 * ★ onReady 首绘 + @Watch 数据变更重绘；无数据时自绘坐标轴与「暂无真实记录」提示。
 */
import { LineChartModel, ChartSeries, ChartPoint } from '../../model/ChartModels';
import { ThemeTokens } from '../../common/ThemeTokens';

const PREVIEW_LINE_MODEL: LineChartModel = {
  title: '温度历史（0 条真实记录）',
  unit: '℃',
  series: []
};

@Component
@Preview
export struct LineChart {
  @Prop @Watch('onModelChange') model: LineChartModel = PREVIEW_LINE_MODEL;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private ready: boolean = false;

  /** 数据模型变化时重绘（声明式重绘，不产生副作用写操作）。 */
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

    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = ThemeTokens.CARD_BACKGROUND;
    ctx.fillRect(0, 0, w, h);

    // 横向网格
    ctx.strokeStyle = ThemeTokens.DIVIDER;
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const y: number = padding + ((h - padding * 2) * i) / 4;
      ctx.beginPath();
      ctx.moveTo(padding, y);
      ctx.lineTo(w - padding, y);
      ctx.stroke();
    }

    // 坐标轴
    ctx.strokeStyle = ThemeTokens.TEXT_HINT;
    ctx.beginPath();
    ctx.moveTo(padding, padding);
    ctx.lineTo(padding, h - padding);
    ctx.lineTo(w - padding, h - padding);
    ctx.stroke();

    // 统计真实点数与数值范围（全部来自传入的 model.series）
    let total: number = 0;
    let maxValue: number = 1;
    let minValue: number = 0;
    for (let s = 0; s < this.model.series.length; s++) {
      const series: ChartSeries = this.model.series[s];
      total = total + series.points.length;
      for (let p = 0; p < series.points.length; p++) {
        const value: number = series.points[p].value;
        if (value > maxValue) {
          maxValue = value;
        }
        if (value < minValue) {
          minValue = value;
        }
      }
    }

    ctx.font = '14px sans-serif';
    if (total === 0) {
      ctx.fillStyle = ThemeTokens.TEXT_HINT;
      ctx.fillText('暂无真实记录（数据来自 EnvironmentLog）', padding + 12, h / 2);
      return;
    }

    const span: number = maxValue - minValue > 0 ? maxValue - minValue : 1;
    const plotW: number = w - padding * 2;
    const plotH: number = h - padding * 2;

    for (let s = 0; s < this.model.series.length; s++) {
      const series: ChartSeries = this.model.series[s];
      const points: ChartPoint[] = series.points;
      if (points.length === 0) {
        continue;
      }
      const denominator: number = points.length > 1 ? points.length - 1 : 1;

      ctx.strokeStyle = series.color.length > 0 ? series.color : ThemeTokens.PRIMARY;
      ctx.lineWidth = 2;
      ctx.beginPath();
      for (let p = 0; p < points.length; p++) {
        const x: number = padding + (plotW * p) / denominator;
        const y: number = padding + plotH - (plotH * (points[p].value - minValue)) / span;
        if (p === 0) {
          ctx.moveTo(x, y);
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();

      // 数据点方块 + 首尾 X 轴刻度（全部自绘，无静态图片）
      ctx.fillStyle = series.color.length > 0 ? series.color : ThemeTokens.PRIMARY;
      for (let p = 0; p < points.length; p++) {
        const x: number = padding + (plotW * p) / denominator;
        const y: number = padding + plotH - (plotH * (points[p].value - minValue)) / span;
        ctx.fillRect(x - 2, y - 2, 4, 4);
      }
      ctx.fillStyle = ThemeTokens.TEXT_SECONDARY;
      ctx.font = '12px sans-serif';
      ctx.fillText(points[0].label, padding, h - padding + 18);
      ctx.fillText(points[points.length - 1].label, w - padding - 60, h - padding + 18);
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
