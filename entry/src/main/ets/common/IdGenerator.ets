/**
 * 智寓 · 唯一 ID 生成器（设计 8.4 / 核验清单第 30 项）
 * util.generateRandomUUID(entropyCache?: boolean): string，前缀 + UUID。
 */
import { util } from '@kit.ArkTS';

export class IdGenerator {
  static device(): string {
    return 'dev_' + util.generateRandomUUID(true);
  }

  static rule(): string {
    return 'rule_' + util.generateRandomUUID(true);
  }

  static condition(): string {
    return 'cond_' + util.generateRandomUUID(true);
  }

  static action(): string {
    return 'act_' + util.generateRandomUUID(true);
  }

  static scene(): string {
    return 'scn_' + util.generateRandomUUID(true);
  }

  static log(): string {
    return 'log_' + util.generateRandomUUID(true);
  }

  /** 通用前缀生成（订阅句柄、诊断项等）。 */
  static withPrefix(prefix: string): string {
    return prefix + '_' + util.generateRandomUUID(true);
  }
}
