/**
 * 智寓 · 单栈路由表（Q-02 裁决 / FR-01-08 / 核验清单第 19/21 项）
 *
 * 10 个 url 常量必须与 entry/src/main/resources/base/profile/main_pages.json
 * 的 src 逐字一致（去掉 .ets 后缀）。禁止 replaceUrl 破坏返回链。
 */
import { router, promptAction } from '@kit.ArkUI';

/**
 * 路由参数载体（显式 interface，供对象字面量在严格类型下获得上下文类型）。
 * ArkTS 禁止对 Record<K, V> 赋非空对象字面量，故用显式 interface 承载。
 * 读取侧见 common/RouteParams.ets。
 */
export interface RouteParamsValue {
  mode?: string;
  deviceId?: string;
  ruleId?: string;
  sceneId?: string;
}

export class RouteMap {
  static readonly INDEX: string = 'pages/Index';
  static readonly DEVICE_LIST: string = 'pages/DeviceList';
  static readonly DEVICE_DETAIL: string = 'pages/DeviceDetail';
  static readonly ENVIRONMENT: string = 'pages/Environment';
  static readonly RULE_LIST: string = 'pages/RuleList';
  static readonly RULE_EDIT: string = 'pages/RuleEdit';
  static readonly SCENE_LIST: string = 'pages/SceneList';
  static readonly SCENE_EDIT: string = 'pages/SceneEdit';
  static readonly STATISTICS: string = 'pages/Statistics';
  static readonly SETTINGS: string = 'pages/Settings';

  /** 与 main_pages.json 逐字一致的 10 项注册表（供一致性自查）。 */
  static readonly ALL: string[] = [
    RouteMap.INDEX,
    RouteMap.DEVICE_LIST,
    RouteMap.DEVICE_DETAIL,
    RouteMap.ENVIRONMENT,
    RouteMap.RULE_LIST,
    RouteMap.RULE_EDIT,
    RouteMap.SCENE_LIST,
    RouteMap.SCENE_EDIT,
    RouteMap.STATISTICS,
    RouteMap.SETTINGS
  ];

  /** 推送新页面；params 用显式 RouteParamsValue 严格类型，禁止传未解析的 Object。 */
  static push(url: string, params?: RouteParamsValue): void {
    if (params === undefined) {
      router.pushUrl({ url: url }).catch((): void => {
        promptAction.showToast({ message: '页面跳转失败：' + url });
      });
      return;
    }
    router.pushUrl({ url: url, params: params }).catch((): void => {
      promptAction.showToast({ message: '页面跳转失败：' + url });
    });
  }

  /** 返回上一页（保存 / 取消 / 详情返回）。 */
  static back(): void {
    router.back();
  }

  /** 数据重置后重建单栈：clear + push 首页（PRD 路由栈结构锁定）。 */
  static resetToIndex(): void {
    router.clear();
    router.pushUrl({ url: RouteMap.INDEX }).catch((): void => {
      promptAction.showToast({ message: '首页重建失败' });
    });
  }

  /** 校验 url 是否已注册，避免跳转到不存在的页面。 */
  static isRegistered(url: string): boolean {
    return RouteMap.ALL.indexOf(url) >= 0;
  }
}
