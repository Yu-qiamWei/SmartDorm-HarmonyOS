/**
 * 智寓 · L2 桩：`@kit.BasicServicesKit`（**仅测试用，不进 HAP**）
 *
 * 真实声明里 `BusinessError` 是「带 `code` / `data` 的 Error」。本项目只读 `err.code`
 * （见 `PreferencesStore.capture()`），故这里只声明这两个成员。
 */
export interface BusinessError extends Error {
  code: number;
  data?: Object;
}
