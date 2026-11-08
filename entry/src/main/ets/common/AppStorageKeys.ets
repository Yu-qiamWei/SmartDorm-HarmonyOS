/**
 * 智寓 · AppStorage 键常量（设计 8.2）
 *
 * AppStorage 仅存放全局单例「引用键」，禁止放 Device[] / Rule[] / 日志等
 * 领域数据，避免与 AppDataRepository 形成双数据源不一致（NFR-03）。
 */
export class AppStorageKeys {
  static readonly REPOSITORY: string = 'smartdorm.repository';
  static readonly THEME: string = 'smartdorm.theme';
  static readonly TIMER_HOST: string = 'smartdorm.timerHost';
}
