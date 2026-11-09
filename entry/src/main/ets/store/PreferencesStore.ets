/**
 * 智寓 · preferences IO 收口（MI-19 / 设计 3.12 / 8.6，任务列表-第四阶段 §4.1）
 *
 * 职责边界（**只做 IO，零业务判断**）：
 *   ① 句柄获取（同步 `getPreferencesSync`）；
 *   ② 启动同步读（`hasSync` / `getSync`）；
 *   ③ 运行异步写（`put` / `delete` / `flush`）；
 *   ④ 收尾同步写（`putSync` / `deleteSync` / `flushSync`）；
 *   ⑤ 所有 `BusinessError` 收口，错误码由 `lastErrorCode()` 暴露给诊断层。
 *
 * ★ 本类**不做**序列化、不判分区、不决定「写什么」——这些属于 `Serializer`（T4-02）
 *   与 `WriteQueue`（T4-01）。因此它不 import 任何 `model/` 或 `store/` 业务类型。
 *
 * ★ 异常二分规则（任务书要求）：
 *   - **读路径与收尾路径吞异常**（`init` / `has` / `getRaw` / `putSync` / `delSync` /
 *     `flushSyncNow`）：进程启动与退出阶段不能因为一次 IO 失败崩溃或抛出未捕获异常；
 *     失败只记录错误码，由调用方按「降级」处理（Q4 / Q6）。
 *   - **运行期写路径重抛**（`put` / `del` / `flushAsync`）：写失败必须让
 *     `WriteQueue` 的逐分区 `try/catch` 看见，从而保持该分区 dirty 并计入
 *     `stats().failures`（§1.2.1 五条规定），不得静默吞成成功。
 *
 * 已核验 API（SDK 5.0.5 / API 17，`api/@ohos.data.preferences.d.ts`）：
 *   `getPreferencesSync(context, options): Preferences` 第 416 行（**只有 `(context, options)` 这一个重载**，
 *   没有 `(context, name)` 同步版——`name` 版只有异步 `getPreferences` 第 336 行）；
 *   `getSync(key, defValue): ValueType` 第 1068 行、`hasSync(key): boolean` 第 1265 行、
 *   `put(key, value): Promise<void>` 第 1371 行、`delete(key): Promise<void>` 第 1500 行、
 *   `flush(): Promise<void>` 第 1665 行、`putSync(key, value): void` 第 1406 行、
 *   `deleteSync(key): void` 第 1531 行、`flushSync(): void` 第 1675 行（`@since 14`，本工程 API 17 可用）。
 *   `clear()` 第 1592 行**不用于重置**（设计 8.6：逐键覆写，保留 `KEY-01`）。
 *
 * 依据：design/任务列表-第四阶段.md 1.1、1.2.1、4.1。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { defaultPreferencesOptions, toSdkOptions } from './PreferencesOptions';

export class PreferencesStore {
  private static instance: PreferencesStore = new PreferencesStore();

  /** 句柄；未 `init` 或 `init` 失败时为 undefined。 */
  private store: preferences.Preferences | undefined = undefined;
  private ready: boolean = false;
  private lastCode: number = 0;

  static getInstance(): PreferencesStore {
    return PreferencesStore.instance;
  }

  private constructor() {
  }

  // ——————————————————————————————————————————————————————————
  // 句柄
  // ——————————————————————————————————————————————————————————

  /**
   * 取句柄（同步）。任何 `BusinessError`（401 参数非法 / 801 能力不支持 /
   * 15500000 内部错误 / 15501001 上下文非 UIAbility / 15501002 token 非法）
   * 都被吞掉并置 `isReady() === false`，**绝不抛到 UI**（Q6「前置未就绪」）。
   *
   * 注意：`getPreferencesSync` 只接受 `(context, options)`，必须传
   * `toSdkOptions(defaultPreferencesOptions())`，不能传 `STORE_NAME` 字符串——
   * 写错会在编译期报 `Options` 类型不匹配，容易被误判成 SDK 版本问题。
   */
  init(context: common.Context): void {
    if (this.ready) {
      return;
    }
    try {
      const options: preferences.Options = toSdkOptions(defaultPreferencesOptions());
      this.store = preferences.getPreferencesSync(context, options);
      this.ready = true;
      this.lastCode = 0;
    } catch (err) {
      this.store = undefined;
      this.ready = false;
      this.capture(err instanceof Error ? err : undefined);
    }
  }

  isReady(): boolean {
    return this.ready && this.store !== undefined;
  }

  // ——————————————————————————————————————————————————————————
  // 启动同步读（吞异常）
  // ——————————————————————————————————————————————————————————

  /** 键是否存在；未就绪或异常返回 false（调用方据此判「首次启动」）。 */
  has(key: string): boolean {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      return false;
    }
    try {
      return handle.hasSync(key);
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
      return false;
    }
  }

  /** 读原始字符串；非 string 值返回 `''`（防 `ValueType` 联合类型泄漏），异常亦返回 `''`。 */
  getRaw(key: string): string {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      return '';
    }
    try {
      const value: preferences.ValueType = handle.getSync(key, '');
      if (typeof value === 'string') {
        return value;
      }
      return '';
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
      return '';
    }
  }

  /**
   * 键名枚举（加载期计算 `trimChunks` 的观测最大块序号用）。未就绪或异常返回 `[]`。
   *
   * ★ **只在 `load()` 里调一次**：`getAllSync()`（声明文件第 1144 行）会把本 store 的全部
   *   value 一起读出来——本项目日志满载时约 1.3 MB。取完键名**立刻丢弃引用**，绝不缓存整表，
   *   否则等于在内存里常驻一份全量副本，与「内存是权威、存储是副本」的分工冲突。
   * ★ 不要退化成「对 `c0000..c9999` 逐个 `hasSync` 探测」：那是一万次系统调用。
   */
  allKeys(): string[] {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      return [];
    }
    try {
      const all: Object = handle.getAllSync();
      if (typeof all !== 'object' || all === null) {
        return [];
      }
      const table: Record<string, Object> = all as Record<string, Object>;
      const keys: string[] = Object.keys(table);
      return keys;
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
      return [];
    }
  }

  // ——————————————————————————————————————————————————————————
  // 运行异步写（重抛）
  // ——————————————————————————————————————————————————————————
  /** 写一个键（分块键或标量键）。失败时记录错误码并**重抛**给 `WriteQueue`。 */
  async put(key: string, json: string): Promise<void> {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      throw new Error('PreferencesStore 未就绪，拒绝写入：' + key);
    }
    try {
      await handle.put(key, json);
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
      throw new Error('preferences.put 失败（key=' + key + ' code=' + this.lastCode + '）');
    }
  }

  /** 删一个键（块收缩用）。失败时记录错误码并**重抛**。 */
  async del(key: string): Promise<void> {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      throw new Error('PreferencesStore 未就绪，拒绝删除：' + key);
    }
    try {
      await handle.delete(key);
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
      throw new Error('preferences.delete 失败（key=' + key + ' code=' + this.lastCode + '）');
    }
  }

  /**
   * 落盘。**一个批次只调用一次**（由 `WriteQueue` 保证，§1.2-C）：
   * 两次跨分区 `put` 在同一次 `flush()` 之前完成，就落在同一次文件写里，
   * 从机制上消除「执行日志有、`lastSatisfied` 没有」导致的重启后规则重复执行风险。
   */
  async flushAsync(): Promise<void> {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      throw new Error('PreferencesStore 未就绪，拒绝落盘');
    }
    try {
      await handle.flush();
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
      throw new Error('preferences.flush 失败（code=' + this.lastCode + '）');
    }
  }

  // ——————————————————————————————————————————————————————————
  // 收尾同步写（吞异常：onDestroy / onWindowStageDestroy 不能崩）
  // ——————————————————————————————————————————————————————————

  putSync(key: string, json: string): void {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      return;
    }
    try {
      handle.putSync(key, json);
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
    }
  }

  delSync(key: string): void {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      return;
    }
    try {
      handle.deleteSync(key);
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
    }
  }

  /** 收尾同步落盘（`flushSync`，`@since 14`，本工程 API 17 可用）。 */
  flushSyncNow(): void {
    const handle: preferences.Preferences | undefined = this.store;
    if (handle === undefined) {
      return;
    }
    try {
      handle.flushSync();
    } catch (err) {
      this.capture(err instanceof Error ? err : undefined);
    }
  }

  // ——————————————————————————————————————————————————————————
  // 诊断
  // ——————————————————————————————————————————————————————————

  /** 最近一次失败的 `BusinessError.code`（0 表示无失败），供 `StorageDiagnostics` 记录。 */
  lastErrorCode(): number {
    return this.lastCode;
  }

  /**
   * 记录错误码。
   *
   * `preferences` 的失败统一以 `BusinessError`（带 `code`）抛出；`err` 为 undefined
   * （捕获到非 `Error` 值）或普通 `Error`（无 `code`）时记为 -1，
   * 便于诊断区分「IO 失败（真实 code）」与「非 IO 异常（-1）」。
   */
  private capture(err: Error | undefined): void {
    if (err === undefined) {
      this.lastCode = -1;
      return;
    }
    const business: BusinessError = err as BusinessError;
    const code: number = business.code;
    this.lastCode = code > 0 ? code : -1;
  }
}
