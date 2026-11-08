/**
 * 智寓 · 时间戳工具（设计 8.4：统一 epoch 毫秒 UTC 存储，展示由本类转本地字符串）
 * 纯函数，无系统 API 依赖。
 */
export class TimeUtil {
  static now(): number {
    return Date.now();
  }

  /** 'MM-DD HH:mm:ss' 本地展示，供日志 / 图表 X 轴标签使用。 */
  static format(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return (
      TimeUtil.pad2(date.getMonth() + 1) + '-' + TimeUtil.pad2(date.getDate()) + ' ' +
      TimeUtil.pad2(date.getHours()) + ':' + TimeUtil.pad2(date.getMinutes()) + ':' +
      TimeUtil.pad2(date.getSeconds())
    );
  }

  /** 'YYYY-MM-DD HH:mm' 本地展示，供列表页使用。 */
  static formatDate(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return (
      date.getFullYear() + '-' + TimeUtil.pad2(date.getMonth() + 1) + '-' +
      TimeUtil.pad2(date.getDate()) + ' ' + TimeUtil.pad2(date.getHours()) + ':' +
      TimeUtil.pad2(date.getMinutes())
    );
  }

  /** 'HH:mm' 供折线图 X 轴刻度使用。 */
  static formatShort(timestamp: number): string {
    const date: Date = new Date(timestamp);
    return TimeUtil.pad2(date.getHours()) + ':' + TimeUtil.pad2(date.getMinutes());
  }

  /** ISO 8601 UTC 字符串，导出 JSON 附带 isoTime 字段便于核查。 */
  static toIsoUtc(timestamp: number): string {
    return new Date(timestamp).toISOString();
  }

  private static pad2(value: number): string {
    return value < 10 ? '0' + value : '' + value;
  }
}
