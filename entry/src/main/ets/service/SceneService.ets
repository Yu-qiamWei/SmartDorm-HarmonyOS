/**
 * 智寓 · 场景服务（MI-14 / FR-05）
 *
 * `apply()` 内部顺序（**不得调换**，见设计 4.9 与任务列表 T3-04）：
 *   ① 场景存在性 → 不存在时返回 `total=0` 的空报告，**不抛异常**（D2）
 *   ② 若「当前场景 = AWAY 且目标 = RETURN」→ 以 `repo.returnSnapshot` 为目标集合恢复（D5）
 *   ③ 若「目标 = AWAY」→ 先把**当前**逐设备状态存为 `returnSnapshot`（FR-05-04 / KEY-10）
 *   ④ 按目标集合逐设备 `setPower` + `setParam`（actor=SCENE），**串行**，单条失败不中断（D3）
 *   ⑤ 聚合 `applied / failed / noChange`，`items[]` 逐条记录 code+message（失败**不得静默**）
 *   ⑥ 写 1 条 `SceneSwitchLog`（含 from/to 与计数，D6）
 *   ⑦ `repo.commitCurrentScene(sceneId, mode)`（含 notify）
 *   ⑧ 返回 `SceneApplyReport`，回寝路径置 `restoredFromSnapshot=true`
 *
 * ★ 场景切换**不经过**写入登记表（护栏 B-7：登记表只服务规则引擎同轮求值，D4），
 *   但**必须**经 `DeviceService` 统一四步校验与 `OperationLog`（actor=SCENE）。
 * ★ 不做整体回滚、也不在首个失败处中断：批量动作按逐设备责任边界聚合（4.9）。
 *
 * 依据：design/系统架构设计.md 4.1 MI-14、4.9、4.5，PRD FR-05-01~06。
 */
import { ISceneService } from './ServiceContracts';
import { DeviceService } from './DeviceService';
import { LogService } from './LogService';
import { AppDataRepository } from '../store/AppDataRepository';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { Device } from '../model/Device';
import {
  DeviceParams, LightParams, AirConditionerParams, CurtainParams, DoorLockParams, FanParams,
  SocketParams
} from '../model/DeviceParams';
import { SceneApplyReport, SceneApplyItem } from '../model/Reports';
import { SceneSwitchLog } from '../model/Logs';
import { CommandResult, okResult, failResult } from '../model/CommandResult';
import { SceneType, RunMode, ParamKey, ResultCode, LogActor, DeviceType } from '../model/Enums';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';

export class SceneService implements ISceneService {
  private static instance: SceneService = new SceneService();

  static getInstance(): SceneService {
    return SceneService.instance;
  }

  private constructor() {
  }

  // ——————————————————————————————————————————————————————
  // MI-14 应用场景
  // ——————————————————————————————————————————————————————

  /** 逐设备下发目标状态；单条失败不中断，最终返回逐项可核查的报告。 */
  async apply(sceneId: string): Promise<SceneApplyReport> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const scene: Scene | undefined = repo.findScene(sceneId);
    const fromSceneId: string = repo.getState().currentSceneId;

    // ① 存在性：返回空报告而非抛异常
    if (scene === undefined) {
      return SceneService.emptyReport(sceneId, fromSceneId);
    }

    // ② 回寝：以 returnSnapshot 为目标集合
    const currentScene: Scene | undefined =
      fromSceneId.length > 0 ? repo.findScene(fromSceneId) : undefined;
    const currentType: SceneType | undefined =
      currentScene === undefined ? undefined : currentScene.type;
    const snapshot: DeviceStateSnapshot[] = repo.getState().returnSnapshot;
    let targets: DeviceStateSnapshot[] = scene.deviceStates.slice();
    let restoredFromSnapshot: boolean = false;
    if (currentType === SceneType.AWAY && scene.type === SceneType.RETURN && snapshot.length > 0) {
      targets = snapshot.slice();
      restoredFromSnapshot = true;
    }

    // ③ 离寝：先保存当前状态（必须在任何设备变更之前）
    if (scene.type === SceneType.AWAY) {
      repo.commitReturnSnapshot(SceneService.capture(repo.getState().devices, TimeUtil.now()));
    }

    // ④ 串行下发，逐条聚合
    const items: SceneApplyItem[] = [];
    for (let i = 0; i < targets.length; i++) {
      items.push(await this.applyOne(targets[i]));
    }

    // ⑤ 计数
    let appliedCount: number = 0;
    let failedCount: number = 0;
    let noChangeCount: number = 0;
    for (let i = 0; i < items.length; i++) {
      const code: ResultCode = items[i].code;
      if (code === ResultCode.OK) {
        appliedCount = appliedCount + 1;
      } else if (code === ResultCode.NO_CHANGE) {
        noChangeCount = noChangeCount + 1;
      } else {
        failedCount = failedCount + 1;
      }
    }

    // ⑥ 场景切换日志（每次切换恰好 1 条）
    const switchLog: SceneSwitchLog = {
      id: IdGenerator.log(),
      timestamp: TimeUtil.now(),
      fromSceneId: fromSceneId,
      toSceneId: scene.id,
      appliedCount: appliedCount,
      failedCount: failedCount
    };
    LogService.getInstance().appendSceneSwitch(switchLog);

    // ⑦ 当前场景与运行模式（写入后由仓储 notify 订阅者刷新首页）
    repo.commitCurrentScene(scene.id, SceneService.modeOf(scene.type));

    // ⑧ 报告
    const report: SceneApplyReport = {
      sceneId: scene.id,
      sceneName: scene.name,
      fromSceneId: fromSceneId,
      appliedAt: switchLog.timestamp,
      total: items.length,
      appliedCount: appliedCount,
      failedCount: failedCount,
      noChangeCount: noChangeCount,
      items: items,
      restoredFromSnapshot: restoredFromSnapshot
    };
    return report;
  }

  // ——————————————————————————————————————————————————————
  // 场景 CRUD
  // ——————————————————————————————————————————————————————

  /** 新建自定义场景：以**当前设备状态**作为初始目标集合（不凭空捏造目标值）。 */
  async create(name: string): Promise<CommandResult<Scene>> {
    const trimmed: string = name.trim();
    if (trimmed.length === 0) {
      return failResult<Scene>(ResultCode.INVALID_PARAM, '场景名称不可为空');
    }
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const now: number = TimeUtil.now();
    const created: Scene = {
      id: IdGenerator.scene(),
      name: trimmed,
      type: SceneType.CUSTOM,
      deviceStates: SceneService.capture(repo.getState().devices, now),
      isPreset: false,
      returnSnapshot: [],
      createdAt: now,
      updatedAt: now
    };
    const scenes: Scene[] = repo.getState().scenes.slice();
    scenes.push(created);
    repo.commitScenes(scenes, 'scene-create');
    return okResult<Scene>(created, '场景「' + created.name + '」已创建');
  }

  /** 更新场景目标集合；预置标记与创建时间不可被覆盖。 */
  async update(scene: Scene): Promise<CommandResult<Scene>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const existing: Scene | undefined = repo.findScene(scene.id);
    if (existing === undefined) {
      return failResult<Scene>(ResultCode.NOT_FOUND, '场景不存在：' + scene.id);
    }
    if (scene.name.trim().length === 0) {
      return failResult<Scene>(ResultCode.INVALID_PARAM, '场景名称不可为空');
    }
    const updated: Scene = {
      id: existing.id,
      name: scene.name.trim(),
      type: existing.type,
      deviceStates: scene.deviceStates.slice(),
      isPreset: existing.isPreset,
      returnSnapshot: existing.returnSnapshot.slice(),
      createdAt: existing.createdAt,
      updatedAt: TimeUtil.now()
    };
    const scenes: Scene[] = repo.getState().scenes;
    const next: Scene[] = [];
    for (let i = 0; i < scenes.length; i++) {
      next.push(scenes[i].id === updated.id ? updated : scenes[i]);
    }
    repo.commitScenes(next, 'scene-update');
    return okResult<Scene>(updated, '场景「' + updated.name + '」已保存');
  }

  /** 删除场景；预置场景不可删（isPreset 校验，FR-05-01）。 */
  async remove(sceneId: string): Promise<CommandResult<void>> {
    const repo: AppDataRepository = AppDataRepository.getInstance();
    const existing: Scene | undefined = repo.findScene(sceneId);
    if (existing === undefined) {
      return failResult<void>(ResultCode.NOT_FOUND, '场景不存在：' + sceneId);
    }
    if (existing.isPreset) {
      return failResult<void>(ResultCode.INVALID_PARAM, '预置场景不可删除，可编辑');
    }
    const kept: Scene[] = [];
    const scenes: Scene[] = repo.getState().scenes;
    for (let i = 0; i < scenes.length; i++) {
      if (scenes[i].id !== sceneId) {
        kept.push(scenes[i]);
      }
    }
    repo.commitScenes(kept, 'scene-remove');
    // 删除的是当前场景时回到手动模式，避免首页指向已不存在的场景
    if (repo.getState().currentSceneId === sceneId) {
      repo.commitCurrentScene('', RunMode.MANUAL);
    }
    return okResult<void>(undefined, '场景「' + existing.name + '」已删除');
  }

  // ——————————————————————————————————————————————————————
  // 内部
  // ——————————————————————————————————————————————————————

  /**
   * 单设备下发：电源 + 各参数，逐项收集结果码。
   * 设备不存在/离线时电源步即失败，**不再**重复下发参数（避免刷出重复失败项）。
   */
  private async applyOne(state: DeviceStateSnapshot): Promise<SceneApplyItem> {
    const service: DeviceService = DeviceService.getInstance();
    const deviceId: string = state.deviceId;
    const codes: ResultCode[] = [];
    let failureMessage: string = '';

    const power: CommandResult<Device> =
      await service.setPower(deviceId, state.powerOn, LogActor.SCENE);
    codes.push(power.code);
    if (!power.success) {
      failureMessage = power.message;
    }
    const blocked: boolean =
      power.code === ResultCode.NOT_FOUND || power.code === ResultCode.DEVICE_OFFLINE;

    if (!blocked) {
      const params: DeviceParams = state.params;
      switch (params.kind) {
        case DeviceType.LIGHT: {
          const result: CommandResult<Device> =
            await service.setParam(deviceId, ParamKey.BRIGHTNESS, params.brightness, LogActor.SCENE);
          codes.push(result.code);
          if (!result.success) {
            failureMessage = result.message;
          }
          break;
        }
        case DeviceType.AIR_CONDITIONER: {
          const temperature: CommandResult<Device> =
            await service.setParam(deviceId, ParamKey.TEMPERATURE, params.temperature, LogActor.SCENE);
          codes.push(temperature.code);
          if (!temperature.success) {
            failureMessage = temperature.message;
          }
          const mode: CommandResult<Device> =
            await service.setParam(deviceId, ParamKey.MODE, params.mode, LogActor.SCENE);
          codes.push(mode.code);
          if (!mode.success) {
            failureMessage = mode.message;
          }
          break;
        }
        case DeviceType.CURTAIN: {
          const result: CommandResult<Device> =
            await service.setParam(deviceId, ParamKey.OPEN_PERCENT, params.openPercent, LogActor.SCENE);
          codes.push(result.code);
          if (!result.success) {
            failureMessage = result.message;
          }
          break;
        }
        case DeviceType.DOOR_LOCK: {
          const result: CommandResult<Device> =
            await service.setParam(deviceId, ParamKey.LOCKED, params.locked, LogActor.SCENE);
          codes.push(result.code);
          if (!result.success) {
            failureMessage = result.message;
          }
          break;
        }
        case DeviceType.FAN: {
          const result: CommandResult<Device> =
            await service.setParam(deviceId, ParamKey.FAN_SPEED, params.fanSpeed, LogActor.SCENE);
          codes.push(result.code);
          if (!result.success) {
            failureMessage = result.message;
          }
          break;
        }
        case DeviceType.SOCKET: {
          const result: CommandResult<Device> =
            await service.setParam(deviceId, ParamKey.POWER_WATT, params.powerWatt, LogActor.SCENE);
          codes.push(result.code);
          if (!result.success) {
            failureMessage = result.message;
          }
          break;
        }
        default: {
          break;
        }
      }
    }
    return SceneService.itemOf(deviceId, codes, failureMessage);
  }

  /** 结果码聚合：任一失败即报失败（部分成功不得美化为成功）；全无变更报 NO_CHANGE。 */
  private static itemOf(
    deviceId: string,
    codes: ResultCode[],
    failureMessage: string
  ): SceneApplyItem {
    let failure: ResultCode | undefined = undefined;
    let hasOk: boolean = false;
    for (let i = 0; i < codes.length; i++) {
      const code: ResultCode = codes[i];
      if (code === ResultCode.OK) {
        hasOk = true;
      } else if (code !== ResultCode.NO_CHANGE && failure === undefined) {
        failure = code;
      }
    }
    if (failure !== undefined) {
      const failed: SceneApplyItem = {
        deviceId: deviceId,
        code: failure,
        message: failureMessage.length > 0 ? failureMessage : ('下发失败：' + failure)
      };
      return failed;
    }
    const done: SceneApplyItem = {
      deviceId: deviceId,
      code: hasOk ? ResultCode.OK : ResultCode.NO_CHANGE,
      message: hasOk ? '已按目标状态下发' : '目标状态未变化'
    };
    return done;
  }

  /** 采集当前设备状态为快照（离寝保存 / 新建场景的初始目标集合）。 */
  private static capture(devices: Device[], now: number): DeviceStateSnapshot[] {
    const result: DeviceStateSnapshot[] = [];
    for (let i = 0; i < devices.length; i++) {
      const device: Device = devices[i];
      const snapshot: DeviceStateSnapshot = {
        deviceId: device.id,
        powerOn: device.powerOn,
        params: SceneService.cloneParams(device.params),
        locked: device.locked,
        online: device.online,
        status: device.status,
        capturedAt: now
      };
      result.push(snapshot);
    }
    return result;
  }

  /** 参数深拷贝（判别收窄后逐类型复制，保证快照不随后续写入漂移）。 */
  private static cloneParams(params: DeviceParams): DeviceParams {
    switch (params.kind) {
      case DeviceType.LIGHT: {
        const next: LightParams = { kind: DeviceType.LIGHT, brightness: params.brightness };
        return next;
      }
      case DeviceType.AIR_CONDITIONER: {
        const next: AirConditionerParams = {
          kind: DeviceType.AIR_CONDITIONER,
          temperature: params.temperature,
          mode: params.mode
        };
        return next;
      }
      case DeviceType.CURTAIN: {
        const next: CurtainParams = { kind: DeviceType.CURTAIN, openPercent: params.openPercent };
        return next;
      }
      case DeviceType.DOOR_LOCK: {
        const next: DoorLockParams = { kind: DeviceType.DOOR_LOCK, locked: params.locked };
        return next;
      }
      case DeviceType.FAN: {
        const next: FanParams = { kind: DeviceType.FAN, fanSpeed: params.fanSpeed };
        return next;
      }
      case DeviceType.SOCKET: {
        const next: SocketParams = { kind: DeviceType.SOCKET, powerWatt: params.powerWatt };
        return next;
      }
      default: {
        const fallback: LightParams = { kind: DeviceType.LIGHT, brightness: 0 };
        return fallback;
      }
    }
  }

  /** 场景类型 → 首页运行模式。 */
  private static modeOf(type: SceneType): RunMode {
    switch (type) {
      case SceneType.STUDY:
        return RunMode.STUDY;
      case SceneType.SLEEP:
        return RunMode.SLEEP;
      case SceneType.AWAY:
        return RunMode.AWAY;
      case SceneType.RETURN:
        return RunMode.RETURN;
      case SceneType.CUSTOM:
        return RunMode.CUSTOM;
      default:
        return RunMode.MANUAL;
    }
  }

  /** 不存在的场景：空报告，不抛异常（D2）。 */
  private static emptyReport(sceneId: string, fromSceneId: string): SceneApplyReport {
    const report: SceneApplyReport = {
      sceneId: sceneId,
      sceneName: '',
      fromSceneId: fromSceneId,
      appliedAt: TimeUtil.now(),
      total: 0,
      appliedCount: 0,
      failedCount: 0,
      noChangeCount: 0,
      items: [],
      restoredFromSnapshot: false
    };
    return report;
  }
}
