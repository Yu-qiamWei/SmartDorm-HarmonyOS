/**
 * 智寓 · L2 桩：`@kit.ArkTS`（**仅测试用，不进 HAP**）
 *
 * 真实 `util.generateRandomUUID(entropyCache?: boolean): string` 产出 v4 UUID。
 * 桩用「进程内自增序号 + 伪随机」拼出形状相同的字符串：L2 只关心
 * 「每次调用都不同」（默认态 id 的唯一性），不关心是否符合 RFC 4122。
 */
export namespace util {
  let counter: number = 0;

  export function generateRandomUUID(entropyCache?: boolean): string {
    counter += 1;
    const a: string = Math.floor(Math.random() * 0xffffffff).toString(16).padStart(8, '0');
    const b: string = counter.toString(16).padStart(8, '0');
    return a + '-' + b.substring(0, 4) + '-4' + b.substring(4, 7) + '-a' +
      a.substring(0, 3) + '-' + a.substring(3, 8) + b.substring(0, 3);
  }
}
