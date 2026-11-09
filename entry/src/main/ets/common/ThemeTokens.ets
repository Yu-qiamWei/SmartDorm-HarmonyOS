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
  /** 触控目标最小高度（T3-06 P6：所有 Button / 可点 Row 高度 ≥ 44vp）。 */
  static readonly TOUCH_MIN_HEIGHT: string = '44vp';

  // —— 响应式断点（T3-06：手机 387.7vp 属 sm 档，平板 ≥ 840vp 起算 md）——
  /** sm 档上限（手机 ≤ 600vp）。 */
  static readonly BREAKPOINT_SM_VP: number = 600;
  /** md 档起点（平板，沿用核验清单第 34 项实测值 840vp）。 */
  static readonly BREAKPOINT_MD_VP: number = 840;
  /** lg 档起点（大屏，三图并排从这一档开始）。 */
  static readonly BREAKPOINT_LG_VP: number = 1200;

  /**
   * 卡片网格列数（设备卡片 / 带两个并排按钮的卡片）。
   * 手机**单列**：卡片内容区在 2 列时仅约 135vp，「查看详情 + 开启」两个按钮会被压到 60vp 上下，
   * 文字截断；单列可用宽度约 315vp，无挤压。
   */
  static readonly GRID_CARDS_PHONE: number = 1;
  static readonly GRID_CARDS_TABLET: number = 2;
  /** 小格子网格列数（首页模块入口 / 设备类型选择 / 统计数字格 / 记录筛选页签）。 */
  static readonly GRID_TILES_PHONE: number = 2;
  static readonly GRID_TILES_TABLET: number = 3;
  /** 图表网格列数（手机单列；平板 2 列；大屏 3 列并排）。 */
  static readonly GRID_CHARTS_PHONE: number = 1;
  static readonly GRID_CHARTS_TABLET: number = 2;
  static readonly GRID_CHARTS_LARGE: number = 3;

  /**
   * @deprecated 旧的两档常量，保留仅为不破坏历史引用；新代码请按语义选
   * `GRID_CARDS_*` / `GRID_TILES_*` / `GRID_CHARTS_*`。
   */
  static readonly BREAKPOINT_TABLET_VP: number = 840;
  /** @deprecated 见 `GRID_TILES_PHONE`。 */
  static readonly GRID_COLUMNS_PHONE: number = 2;
  /** @deprecated 见 `GRID_TILES_TABLET`。 */
  static readonly GRID_COLUMNS_TABLET: number = 3;

  /** 生成 mediaquery 条件字符串，避免在页面里硬编码断点数值。 */
  static tabletQuery(): string {
    return '(min-width: ' + ThemeTokens.BREAKPOINT_MD_VP + 'vp)';
  }

  /** 大屏断点查询（三图并排等场景用）。 */
  static largeQuery(): string {
    return '(min-width: ' + ThemeTokens.BREAKPOINT_LG_VP + 'vp)';
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
