/**
 * 智寓 · 统一视觉设计令牌（NFR-10 现代化智能家居控制中心风格）
 *
 * 所有页面与组件只从本类取色值 / 圆角 / 间距 / 字号，禁止散落硬编码色值。
 * 取值与 entry/src/main/resources/base/element/color.json、float.json 对齐。
 * 依据：design/系统架构设计.md 8.1 命名规范、T-03 验收 C1/C7。
 */
export class ThemeTokens {
  // —— 颜色（与 color.json 逐项一致）——
  static readonly PRIMARY: string = '#2F6BFF';
  static readonly PRIMARY_DARK: string = '#1D47B8';
  static readonly ACCENT: string = '#00B8A9';
  static readonly PAGE_BACKGROUND: string = '#F2F5FA';
  static readonly CARD_BACKGROUND: string = '#FFFFFF';
  static readonly TEXT_PRIMARY: string = '#1B2333';
  static readonly TEXT_SECONDARY: string = '#6B768C';
  static readonly TEXT_HINT: string = '#98A2B3';
  static readonly TEXT_ON_PRIMARY: string = '#FFFFFF';
  static readonly DIVIDER: string = '#E3E8F0';
  static readonly STATUS_RUNNING: string = '#12A97B';
  static readonly STATUS_IDLE: string = '#8792A6';
  static readonly STATUS_FAULT: string = '#E8562E';
  static readonly STATUS_OFFLINE: string = '#8C4BE0';
  static readonly WARNING_BACKGROUND: string = '#FFF3E8';

  // —— 圆角 / 间距 / 字号（与 float.json 一致）——
  static readonly RADIUS_CARD: string = '20vp';
  static readonly RADIUS_CONTROL: string = '12vp';
  static readonly RADIUS_BADGE: string = '8vp';
  static readonly SPACE_PAGE_X: string = '20vp';
  static readonly SPACE_CARD_PADDING: string = '16vp';
  static readonly SPACE_ITEM_GAP: string = '12vp';
  static readonly SPACE_SECTION_GAP: string = '20vp';
  static readonly FONT_TITLE_LARGE: string = '26fp';
  static readonly FONT_TITLE_MEDIUM: string = '20fp';
  static readonly FONT_BODY: string = '15fp';
  static readonly FONT_CAPTION: string = '12fp';
  static readonly CARD_MIN_HEIGHT: string = '120vp';
  static readonly CHART_HEIGHT: string = '220vp';

  // —— 平板响应式断点（mediaquery + GridRow/GridCol，核验清单第 34 项）——
  static readonly BREAKPOINT_TABLET_VP: number = 840;
  static readonly GRID_COLUMNS_PHONE: number = 2;
  static readonly GRID_COLUMNS_TABLET: number = 3;

  /** 生成 mediaquery 条件字符串，避免在页面里硬编码断点数值。 */
  static tabletQuery(): string {
    return '(min-width: ' + ThemeTokens.BREAKPOINT_TABLET_VP + 'vp)';
  }

  /** 四态徽标配色（FAULT / OFFLINE 明显区别于 RUNNING / IDLE，FR-01-06）。 */
  static statusColor(status: string): string {
    switch (status) {
      case 'RUNNING':
        return ThemeTokens.STATUS_RUNNING;
      case 'IDLE':
        return ThemeTokens.STATUS_IDLE;
      case 'FAULT':
        return ThemeTokens.STATUS_FAULT;
      case 'OFFLINE':
        return ThemeTokens.STATUS_OFFLINE;
      default:
        return ThemeTokens.TEXT_HINT;
    }
  }

  /** 四态徽标中文标签。 */
  static statusLabel(status: string): string {
    switch (status) {
      case 'RUNNING':
        return '运行中';
      case 'IDLE':
        return '空闲';
      case 'FAULT':
        return '故障';
      case 'OFFLINE':
        return '离线';
      default:
        return '未知';
    }
  }
}
