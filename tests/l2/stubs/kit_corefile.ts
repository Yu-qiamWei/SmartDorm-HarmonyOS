/**
 * 测试桩：`@kit.CoreFileKit`（仅覆盖 ExportService 用到的符号）。
 * 永不进入 HAP；仅供 Node 侧 tsc 类型消解。
 */
export namespace fileIo {
  export enum OpenMode {
    READ_ONLY = 0o0,
    WRITE_ONLY = 0o1,
    READ_WRITE = 0o2,
    CREATE = 0o100,
    TRUNC = 0o1000,
    APPEND = 0o2000
  }

  export interface File {
    fd: number;
  }

  export function accessSync(path: string): boolean {
    return true;
  }

  export function mkdirSync(path: string, recursive?: boolean): void {
  }

  export function openSync(path: string, mode: OpenMode): File {
    return { fd: 0 };
  }

  export function writeSync(fd: number | File, content: string): number {
    return content.length;
  }

  export function closeSync(file: number | File): void {
  }
}
