/**
 * 智寓 · 路由参数严格解析（设计 AT-02 / Q-02 / 核验清单第 19 项）
 *
 * router.getParams() 的返回值必须经本类断言为 Record<string, string> 后再用，
 * 禁止把宽类型当领域对象用；所有读取都有安全默认值，绝不返回 undefined。
 */
import { router } from '@kit.ArkUI';

export class RouteParams {
  /** 读取单个字符串参数，缺失 / 空串 / 非字符串时返回默认值。 */
  static getString(key: string, defaultValue: string): string {
    const raw: Record<string, string> | undefined =
      router.getParams() as Record<string, string> | undefined;
    if (raw === undefined || raw === null) {
      return defaultValue;
    }
    const value: string = raw[key];
    if (typeof value !== 'string' || value.length === 0) {
      return defaultValue;
    }
    return value;
  }

  /** 解析后的完整参数表（无参数时返回空 Record，绝不返回 undefined）。 */
  static all(): Record<string, string> {
    const empty: Record<string, string> = {};
    const raw: Record<string, string> | undefined =
      router.getParams() as Record<string, string> | undefined;
    if (raw === undefined || raw === null) {
      return empty;
    }
    return raw;
  }

  /** 列表 → 设备详情（FR-01-04）。 */
  static deviceId(): string {
    return RouteParams.getString('deviceId', '');
  }

  /** 列表 → 规则编辑（修改模式）。 */
  static ruleId(): string {
    return RouteParams.getString('ruleId', '');
  }

  /** 列表 → 场景编辑。 */
  static sceneId(): string {
    return RouteParams.getString('sceneId', '');
  }

  /** 新建 / 编辑模式，默认 create。 */
  static mode(): string {
    return RouteParams.getString('mode', 'create');
  }
}
