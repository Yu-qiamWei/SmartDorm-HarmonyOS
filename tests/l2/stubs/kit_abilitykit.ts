/**
 * 智寓 · L2 桩：`@kit.AbilityKit`（**仅测试用，不进 HAP**）
 *
 * 只声明 `common.Context`。L2 里 `PreferencesStore.init(context)` 的入参就是这个类型的实例，
 * 而真实 `Context` 需要 UIAbility 运行时才有（Node 侧不存在），故以最小接口代替：
 * 本项目 `PreferencesStore` 从不读取 `Context` 的任何成员，只把它转交给
 * `preferences.getPreferencesSync(context, options)`——桩里的同名函数同样忽略它。
 *
 * `filesDir` 保留为可选字段，是为了让「看起来像真 Context」的测试夹具能通过类型检查。
 */
export namespace common {
  export interface Context {
    readonly filesDir?: string;
    readonly databaseDir?: string;
    readonly cacheDir?: string;
  }
}
