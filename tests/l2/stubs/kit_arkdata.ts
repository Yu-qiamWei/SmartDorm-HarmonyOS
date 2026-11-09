/**
 * 智寓 · L2 桩：`@kit.ArkData` 的 `preferences`（**仅测试用，不进 HAP**）
 *
 * 为什么需要它：T4-03 的 `AppDataRepository.load/flush/saveNowSync/reset` 只有在
 * `preferences` 可用的前提下才能被真实驱动。Node 侧没有鸿蒙运行时，所以这里给一份
 * **内存 + 磁盘两层**的假实现，语义对齐真实 API：
 *
 *   - `put` / `putSync`：只改**内存**（真实 preferences 同样是先改内存缓存）；
 *   - `flush` / `flushSync`：内存 → **磁盘**（真实实现此时才写文件）；
 *   - `hasSync` / `getSync` / `getAllSync`：读内存。
 *
 * 有了「内存 / 磁盘」两层，L2 才能断言「落盘失败时磁盘内容未变」，
 * 否则「写失败」与「写成功」在测试里无法区分——那是 C10 能不能成立的关键。
 *
 * 故障注入：`FakePrefsControl` 是唯一的控制面（`failPut` / `failDelete` / `failFlush` /
 * `failSync` 都按「接下来 n 次调用抛错」计数），用来构造 `STORAGE_ERROR` 路径（C10 系列）。
 *
 * ★ 本文件不是生产代码，也不会被 `gen.js` 之外的任何东西引用；改动它不影响 HAP。
 */
import { common } from '@kit.AbilityKit';

/** 假 `BusinessError`：真实 preferences 的失败都带 `code`，`PreferencesStore.capture()` 要读它。 */
class FakeBusinessError extends Error {
  code: number = 15500000;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

export namespace preferences {
  export type ValueType =
    number | string | boolean | Array<number> | Array<string> | Array<boolean> | Uint8Array | Object | bigint;

  /** 真实声明：`interface Options { name: string; dataGroupId?: string | null; }`。 */
  export interface Options {
    name: string;
    dataGroupId?: string | null;
  }

  /** 本项目用到的 `Preferences` 子集（对照 api/@ohos.data.preferences.d.ts 的行号见 PreferencesStore 头注释）。 */
  export interface Preferences {
    hasSync(key: string): boolean;
    getSync(key: string, defValue: ValueType): ValueType;
    getAllSync(): Object;
    put(key: string, value: ValueType): Promise<void>;
    delete(key: string): Promise<void>;
    flush(): Promise<void>;
    putSync(key: string, value: ValueType): void;
    deleteSync(key: string): void;
    flushSync(): void;
  }

  export function getPreferencesSync(context: common.Context, options: Options): Preferences {
    return FakePrefsControl.handleOf(options.name);
  }
}

/** 故障注入 + 观测面（L2 专用）。计数语义：正整数 = 接下来 n 次调用抛错。 */
export class FakePrefsControl {
  private static stores: Map<string, FakePreferences> = new Map<string, FakePreferences>();
  private static putFailures: number = 0;
  private static deleteFailures: number = 0;
  private static flushFailures: number = 0;
  private static syncFailures: number = 0;

  /** 取（或新建）某个 store 名的句柄。生产代码永远只经 `getPreferencesSync` 拿到它。 */
  static handleOf(name: string): FakePreferences {
    const existing: FakePreferences | undefined = FakePrefsControl.stores.get(name);
    if (existing !== undefined) {
      return existing;
    }
    const created: FakePreferences = new FakePreferences();
    FakePrefsControl.stores.set(name, created);
    return created;
  }

  /** 清空所有 store 与所有故障计数（每个用例开头调一次，避免用例间串味）。 */
  static reset(): void {
    FakePrefsControl.stores.clear();
    FakePrefsControl.putFailures = 0;
    FakePrefsControl.deleteFailures = 0;
    FakePrefsControl.flushFailures = 0;
    FakePrefsControl.syncFailures = 0;
  }

  /**
   * 模拟进程重启：内存回退成磁盘内容。
   *
   * 这正是真机冷启动的效果——未 `flush` 的写入随进程一起消失。
   * 「写成功」的用例里磁盘已有数据，`restart()` 后仍然读得到；
   * 「写失败」的用例里磁盘没变，`restart()` 后读到的就是旧值。
   */
  static restart(): void {
    FakePrefsControl.stores.forEach((handle: FakePreferences): void => {
      handle.reloadFromDisk();
    });
  }

  /** 接下来 `times` 次 `put` / `delete` / `flush` / 同步写抛 `BusinessError`。 */
  static failPut(times: number): void {
    FakePrefsControl.putFailures = times;
  }

  static failDelete(times: number): void {
    FakePrefsControl.deleteFailures = times;
  }

  static failFlush(times: number): void {
    FakePrefsControl.flushFailures = times;
  }

  /** 同步写（`putSync` / `deleteSync` / `flushSync`）失败。 */
  static failSync(times: number): void {
    FakePrefsControl.syncFailures = times;
  }

  /**
   * 落盘内容（磁盘层）的只读副本。
   *
   * 键名清单即真机上 `preferences/smartdorm_store` 里的键，值即 JSON 原文，
   * 因此 L2 也能断言「键名形状正确」（例如没有 `smartdorm.meta.schemaVersion.hdr` 这种垃圾键）。
   */
  static diskOf(name: string): Map<string, string> {
    return FakePrefsControl.handleOf(name).diskCopy();
  }

  /** 内存内容副本（未落盘的部分也在这里）。 */
  static memoryOf(name: string): Map<string, string> {
    return FakePrefsControl.handleOf(name).memoryCopy();
  }

  /** 取下一次 `put` 计数（生产代码内部用；对外不暴露计数）。 */
  static takePutFailure(): boolean {
    if (FakePrefsControl.putFailures > 0) {
      FakePrefsControl.putFailures -= 1;
      return true;
    }
    return false;
  }

  static takeDeleteFailure(): boolean {
    if (FakePrefsControl.deleteFailures > 0) {
      FakePrefsControl.deleteFailures -= 1;
      return true;
    }
    return false;
  }

  static takeFlushFailure(): boolean {
    if (FakePrefsControl.flushFailures > 0) {
      FakePrefsControl.flushFailures -= 1;
      return true;
    }
    return false;
  }

  static takeSyncFailure(): boolean {
    if (FakePrefsControl.syncFailures > 0) {
      FakePrefsControl.syncFailures -= 1;
      return true;
    }
    return false;
  }
}

/** 假句柄本体。 */
export class FakePreferences implements preferences.Preferences {
  private mem: Map<string, Object> = new Map<string, Object>();
  private disk: Map<string, Object> = new Map<string, Object>();

  hasSync(key: string): boolean {
    return this.mem.has(key);
  }

  getSync(key: string, defValue: preferences.ValueType): preferences.ValueType {
    const value: Object | undefined = this.mem.get(key);
    if (value === undefined) {
      return defValue;
    }
    return value as preferences.ValueType;
  }

  getAllSync(): Object {
    const table: Record<string, Object> = {};
    this.mem.forEach((value: Object, key: string): void => {
      table[key] = value;
    });
    return table;
  }

  async put(key: string, value: preferences.ValueType): Promise<void> {
    if (FakePrefsControl.takePutFailure()) {
      throw new FakeBusinessError(15500000, 'fake put failure: ' + key);
    }
    this.mem.set(key, value);
  }

  async delete(key: string): Promise<void> {
    if (FakePrefsControl.takeDeleteFailure()) {
      throw new FakeBusinessError(15500000, 'fake delete failure: ' + key);
    }
    this.mem.delete(key);
  }

  async flush(): Promise<void> {
    if (FakePrefsControl.takeFlushFailure()) {
      throw new FakeBusinessError(15500000, 'fake flush failure');
    }
    this.disk = new Map<string, Object>(this.mem);
  }

  putSync(key: string, value: preferences.ValueType): void {
    if (FakePrefsControl.takeSyncFailure()) {
      throw new FakeBusinessError(15500000, 'fake putSync failure: ' + key);
    }
    this.mem.set(key, value);
  }

  deleteSync(key: string): void {
    if (FakePrefsControl.takeSyncFailure()) {
      throw new FakeBusinessError(15500000, 'fake deleteSync failure: ' + key);
    }
    this.mem.delete(key);
  }

  flushSync(): void {
    if (FakePrefsControl.takeSyncFailure()) {
      throw new FakeBusinessError(15500000, 'fake flushSync failure');
    }
    this.disk = new Map<string, Object>(this.mem);
  }

  /** 进程重启：内存丢掉，回到磁盘内容。 */
  reloadFromDisk(): void {
    this.mem = new Map<string, Object>(this.disk);
  }

  diskCopy(): Map<string, string> {
    return FakePreferences.stringCopyOf(this.disk);
  }

  memoryCopy(): Map<string, string> {
    return FakePreferences.stringCopyOf(this.mem);
  }

  private static stringCopyOf(source: Map<string, Object>): Map<string, string> {
    const copy: Map<string, string> = new Map<string, string>();
    source.forEach((value: Object, key: string): void => {
      copy.set(key, typeof value === 'string' ? value : String(value));
    });
    return copy;
  }
}
