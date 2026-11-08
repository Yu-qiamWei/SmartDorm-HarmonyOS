/**
 * 智寓 · 图表数据模型（Q-03 / FR-06-02/03）
 *
 * 依据：design/系统架构设计.md 3.13 节。
 * ★ 禁止静态图片护栏：LineChart / BarChart 只接收本文件定义的模型，
 * 组件内不引用任何图片资源、不内嵌预置数据点；数据来自真实日志聚合（ST-03）。
 */
export interface ChartPoint {
  label: string; // X 轴刻度（格式化时间）
  value: number; // Y 轴数值
  timestamp: number; // epoch ms UTC，来自真实日志
}

export interface ChartBar {
  label: string; // 分类名（设备类型 / 规则 / 状态）
  value: number; // 由真实日志计数得来
}

export interface ChartSeries {
  seriesName: string;
  color: string;
  points: ChartPoint[];
}

export interface LineChartModel {
  title: string;
  unit: string; // '℃' / '%RH' / 'AQI'
  series: ChartSeries[]; // 至少 1 条；禁止空数组外硬编码点
  min?: number;
  max?: number;
}

export interface BarChartModel {
  title: string;
  unit: string; // '次' / '条'
  bars: ChartBar[]; // 由 StatisticsService 聚合真实日志得出
  color: string;
}
