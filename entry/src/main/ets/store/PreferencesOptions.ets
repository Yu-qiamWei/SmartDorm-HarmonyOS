/**
 * 智寓 · preferences.Options 包装（Q-01 / 设计 3.12 / 核验清单第 3 项）
 *
 * SDK 声明：interface Options { name: string; dataGroupId?: string | null | undefined; }
 * 本项目不使用应用组（不设置 dataGroupId）；ST-04 用 toSdkOptions() 取句柄。
 */
import { preferences } from '@kit.ArkData';
import { STORE_NAME } from '../common/Constants';

export interface PreferencesOptions {
  name: string; // 固定 'smartdorm_store'
  dataGroupId?: string | null; // 本项目不设置
}

/** 默认选项（唯一实例来源，避免各处硬编码 store 名）。 */
export function defaultPreferencesOptions(): PreferencesOptions {
  const options: PreferencesOptions = { name: STORE_NAME };
  return options;
}

/** 转换成本项目 SDK 声明的 preferences.Options（getPreferencesSync 入参）。 */
export function toSdkOptions(o: PreferencesOptions): preferences.Options {
  const sdk: preferences.Options = { name: o.name };
  if (o.dataGroupId !== undefined && o.dataGroupId !== null) {
    sdk.dataGroupId = o.dataGroupId;
  }
  return sdk;
}
