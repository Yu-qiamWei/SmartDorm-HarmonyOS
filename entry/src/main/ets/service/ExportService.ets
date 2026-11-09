/**
 * 智寓 · 沙箱导出服务（FR-07-04 / P1）
 *
 * 能力边界：只写应用沙箱 `context.filesDir/exports/`，**不**调用跨应用分享
 * （`fileShare` / `picker` 属 P2，明确不纳入本阶段）。
 *
 * 为什么是这类写法：
 *   - `context` 只能从 `UIAbility` 注入（与阶段四 `PreferencesStore` 同一注入点），
 *     本类不 import 任何 Ability 单例，避免 service 层反向依赖入口层；
 *   - 文件写用**同步** API（`accessSync / mkdirSync / openSync / writeSync / closeSync`），
 *     导出是用户点按的一次性小文件操作，同步写法不会阻塞采样链路（不同线程）；
 *   - `writeSync` 放在 `try/finally` 内，保证任何异常路径都会 `closeSync` 释放句柄。
 *
 * 已核验 API（SDK 5.0.5 / API 17）：
 *   `fileIo.accessSync(path): boolean`、`fileIo.mkdirSync(path, recursion)`、
 *   `fileIo.openSync(path, mode): File`、`fileIo.writeSync(fd, buffer): number`、
 *   `fileIo.closeSync(file: number | File): void`、`context.filesDir`。
 *
 * 依据：design/系统架构设计.md 4.1 MI-19 / 9 章核验清单，PRD FR-07-04。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { AutomationRule } from '../model/AutomationRule';
import { AppSettings } from '../model/AppSettings';
import { EnvironmentData } from '../model/EnvironmentData';
import { RunMode, ResultCode } from '../model/Enums';
import { CommandResult, okResult, failResult } from '../model/CommandResult';
import { DeviceParamsFactory } from '../model/DeviceParams';
import { EXPORT_DIR_NAME } from '../common/Constants';
import { TimeUtil } from '../common/TimeUtil';
import { IExportService } from './ServiceContracts';
import { AppDataRepository } from '../store/AppDataRepository';

/** 导出日志条数汇总（不含日志正文，正文规模由阶段四决定是否分文件）。 */
export interface ExportLogCounts {
  operation: number;
  ruleExecution: number;
  environment: number;
  sceneSwitch: number;
}

/** JSON 导出载荷（显式 interface：ArkTS 严格类型禁止无类型对象字面量）。 */
export interface ExportPayload {
  schemaVersion: number;
  exportedAt: number;
  isoTime: string;
  appVersion: string;
  deviceCount: number;
  ruleCount: number;
  sceneCount: number;
  logCounts: ExportLogCounts;
  devices: Device[];
  rules: AutomationRule[];
  scenes: Scene[];
  settings: AppSettings;
  environment: EnvironmentData;
  returnSnapshot: DeviceStateSnapshot[];
  currentMode: RunMode;
  currentSceneId: string;
}

export class ExportService implements IExportService {
  private static instance: ExportService = new ExportService();

  private context: common.Context | undefined = undefined;

  static getInstance(): ExportService {
    return ExportService.instance;
  }

  private constructor() {
  }

  /** 由 `EntryAbility.onCreate` 注入应用上下文（与阶段四持久化共用同一注入点）。 */
  init(context: common.Context): void {
    this.context = context;
  }

  /** 是否已注入上下文（诊断用；未注入时导出返回 STORAGE_ERROR 而不是崩溃）。 */
  isReady(): boolean {
    return this.context !== undefined;
  }

  /**
   * 导出当前内存态到 `filesDir/exports/export_<epochMs>.json|csv`。
   * 返回值为**真实写入的文件绝对路径**；写入 0 字节视为失败（不谎报成功）。
   */
  async exportToFilesDir(state: AppState, format: string): Promise<CommandResult<string>> {
    const context: common.Context | undefined = this.context;
    if (context === undefined) {
      return failResult<string>(
        ResultCode.STORAGE_ERROR, '导出未初始化：缺少应用上下文（应在 EntryAbility.onCreate 注入）'
      );
    }
    // 需求4：导出前先等待持久化完成，避免「导出成功但数据仍未落盘」。
    // 若落盘失败（存储不可用），中止导出并返回 STORAGE_ERROR，绝不谎报导出成功。
    const persisted: CommandResult<void> = await AppDataRepository.getInstance().flush();
    if (persisted.code !== ResultCode.OK && persisted.code !== ResultCode.NO_CHANGE) {
      return failResult<string>(
        ResultCode.STORAGE_ERROR, '导出前持久化失败，已中止导出：' + persisted.message
      );
    }
    const isCsv: boolean = format.toLowerCase() === 'csv';
    const stamp: number = TimeUtil.now();
    const dir: string = context.filesDir + '/' + EXPORT_DIR_NAME;
    const path: string = dir + '/export_' + stamp + (isCsv ? '.csv' : '.json');
    const content: string = isCsv ? ExportService.toCsv(state) : ExportService.toJson(state);

    try {
      if (!fileIo.accessSync(dir)) {
        fileIo.mkdirSync(dir, true);
      }
      const file = fileIo.openSync(
        path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      let written: number = 0;
      try {
        written = fileIo.writeSync(file.fd, content);
      } finally {
        fileIo.closeSync(file);
      }
      if (written <= 0) {
        return failResult<string>(ResultCode.STORAGE_ERROR, '导出写入 0 字节：' + path);
      }
      return okResult<string>(path, '已导出 ' + written + ' 字节到 ' + path);
    } catch (err) {
      return failResult<string>(
        ResultCode.STORAGE_ERROR,
        '导出失败：' + (err instanceof Error ? err.message : '未知错误')
      );
    }
  }

  // ——————————————————————————————————————————————————————
  // 序列化（确定性、字段顺序固定）
  // ——————————————————————————————————————————————————————

  private static toJson(state: AppState): string {
    const now: number = TimeUtil.now();
    const counts: ExportLogCounts = {
      operation: state.logs.operations.length,
      ruleExecution: state.logs.ruleExecutions.length,
      environment: state.logs.environment.length,
      sceneSwitch: state.logs.sceneSwitches.length
    };
    const payload: ExportPayload = {
      schemaVersion: state.schemaVersion,
      exportedAt: now,
      isoTime: TimeUtil.toIsoUtc(now),
      appVersion: state.settings.appVersion,
      deviceCount: state.devices.length,
      ruleCount: state.rules.length,
      sceneCount: state.scenes.length,
      logCounts: counts,
      devices: state.devices,
      rules: state.rules,
      scenes: state.scenes,
      settings: state.settings,
      environment: state.environment,
      returnSnapshot: state.returnSnapshot,
      currentMode: state.currentMode,
      currentSceneId: state.currentSceneId
    };
    return JSON.stringify(payload);
  }

  /**
   * CSV 导出：只导出**设备清单**（一行一台）。
   * 复杂嵌套结构（规则条件/动作、日志）用 CSV 表达会丢语义，故只提供 JSON 全量导出，
   * 这里不假装 CSV 等价于全量导出。
   */
  private static toCsv(state: AppState): string {
    const lines: string[] = [];
    lines.push('deviceId,name,type,powerOn,online,status,locked,params,lastUpdatedIso');
    for (let i = 0; i < state.devices.length; i++) {
      const device: Device = state.devices[i];
      lines.push(
        device.id + ',' +
        ExportService.escape(device.name) + ',' +
        device.type + ',' +
        (device.powerOn ? 'true' : 'false') + ',' +
        (device.online ? 'true' : 'false') + ',' +
        device.status + ',' +
        (device.locked ? 'true' : 'false') + ',' +
        ExportService.escape(DeviceParamsFactory.describe(device.params)) + ',' +
        TimeUtil.toIsoUtc(device.lastUpdated)
      );
    }
    return lines.join('\n');
  }

  /** CSV 字段转义：含逗号/引号/换行时用双引号包裹并转义内部引号。 */
  private static escape(value: string): string {
    if (value.indexOf(',') < 0 && value.indexOf('"') < 0 && value.indexOf('\n') < 0) {
      return value;
    }
    return '"' + value.split('"').join('""') + '"';
  }
}
