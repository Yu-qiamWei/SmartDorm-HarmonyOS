/**
 * 智寓 · 首次启动默认数据工厂（阶段二占位 / 架构 #80）
 *
 * 产出：6 类设备、5 传感器初值、4 预置场景（含真实目标状态集合）、
 * 空规则、空四类日志、默认设置。★★ logs.ruleExecutions 恒为 []（护栏 A-6 / B6），
 * 禁止预置任何演示执行日志；规则也必须由用户在界面上创建（FR-08-02/05）。
 *
 * 阶段二：只提供内存态默认数据供页面渲染，不写持久化（ST-04 接首次启动落盘）。
 */
import { AppState } from '../model/AppState';
import { Device } from '../model/Device';
import { EnvironmentData } from '../model/EnvironmentData';
import { AutomationRule } from '../model/AutomationRule';
import { Scene, DeviceStateSnapshot } from '../model/Scene';
import { LogBundle } from '../model/Logs';
import { AppSettings } from '../model/AppSettings';
import { DeviceParamsFactory } from '../model/DeviceParams';
import {
  DeviceType, DeviceStatus, SceneType, EnvSource, RunMode
} from '../model/Enums';
import { IdGenerator } from '../common/IdGenerator';
import { TimeUtil } from '../common/TimeUtil';
import {
  SCHEMA_VERSION, DEFAULT_SAMPLE_INTERVAL_MS, DEFAULT_LOG_LIMIT, APP_VERSION
} from '../common/Constants';

export class MockDataFactory {
  /** 单一数据源默认状态（AppDataRepository 单例持有，页面只读）。 */
  static createDefaultAppState(): AppState {
    const now: number = TimeUtil.now();
    const devices: Device[] = MockDataFactory.createDefaultDevices(now);
    const scenes: Scene[] = MockDataFactory.createPresetScenes(devices, now);
    const environment: EnvironmentData = MockDataFactory.createDefaultEnvironment(now);
    const settings: AppSettings = MockDataFactory.createDefaultSettings();
    const logs: LogBundle = {
      operations: [],
      ruleExecutions: [],
      environment: [],
      sceneSwitches: []
    };
    const rules: AutomationRule[] = [];
    const returnSnapshot: DeviceStateSnapshot[] = [];
    const state: AppState = {
      schemaVersion: SCHEMA_VERSION,
      devices: devices,
      rules: rules,
      scenes: scenes,
      settings: settings,
      environment: environment,
      logs: logs,
      returnSnapshot: returnSnapshot,
      currentMode: RunMode.MANUAL,
      currentSceneId: ''
    };
    return state;
  }

  /** 六类设备，各自独立状态与默认参数（FR-01-03）。 */
  static createDefaultDevices(now: number): Device[] {
    const types: DeviceType[] = [
      DeviceType.LIGHT,
      DeviceType.AIR_CONDITIONER,
      DeviceType.CURTAIN,
      DeviceType.DOOR_LOCK,
      DeviceType.FAN,
      DeviceType.SOCKET
    ];
    const names: string[] = [
      '智能灯光', '智能空调', '智能窗帘', '智能门锁', '智能风扇', '智能插座'
    ];
    const result: Device[] = [];
    for (let i = 0; i < types.length; i++) {
      const type: DeviceType = types[i];
      const device: Device = {
        id: IdGenerator.device(),
        name: names[i],
        type: type,
        powerOn: false,
        params: DeviceParamsFactory.defaults(type),
        online: true,
        status: DeviceStatus.IDLE,
        locked: type === DeviceType.DOOR_LOCK,
        createdAt: now,
        lastUpdated: now
      };
      result.push(device);
    }
    return result;
  }

  /** 5 类传感器初值（PRD 4.4 基线，非固定展示常量）。 */
  static createDefaultEnvironment(now: number): EnvironmentData {
    const data: EnvironmentData = {
      temperature: 25,
      humidity: 50,
      illuminance: 300,
      airQuality: 50,
      humanPresence: false,
      timestamp: now,
      source: EnvSource.INIT
    };
    return data;
  }

  /** 默认设置（DM-11 / FR-07）。 */
  static createDefaultSettings(): AppSettings {
    const settings: AppSettings = {
      automationEnabled: true,
      simulationEnabled: true,
      sampleIntervalMs: DEFAULT_SAMPLE_INTERVAL_MS,
      logLimit: DEFAULT_LOG_LIMIT,
      schemaVersion: SCHEMA_VERSION,
      appVersion: APP_VERSION
    };
    return settings;
  }

  /** 四个预置场景 + 逐设备目标状态集合（FR-05-01/05）。 */
  static createPresetScenes(devices: Device[], now: number): Scene[] {
    const types: SceneType[] = [
      SceneType.STUDY, SceneType.SLEEP, SceneType.AWAY, SceneType.RETURN
    ];
    const names: string[] = ['学习模式', '睡眠模式', '离寝模式', '回寝模式'];
    const result: Scene[] = [];
    for (let i = 0; i < types.length; i++) {
      const sceneType: SceneType = types[i];
      const scene: Scene = {
        id: IdGenerator.scene(),
        name: names[i],
        type: sceneType,
        deviceStates: MockDataFactory.buildTargetStates(devices, sceneType, now),
        isPreset: true,
        returnSnapshot: [],
        createdAt: now,
        updatedAt: now
      };
      result.push(scene);
    }
    return result;
  }

  /** 新建自定义场景（SceneEdit 页真实调用，id 唯一）。 */
  static createCustomScene(name: string, devices: Device[], now: number): Scene {
    const scene: Scene = {
      id: IdGenerator.scene(),
      name: name,
      type: SceneType.CUSTOM,
      deviceStates: MockDataFactory.buildTargetStates(devices, SceneType.CUSTOM, now),
      isPreset: false,
      returnSnapshot: [],
      createdAt: now,
      updatedAt: now
    };
    return scene;
  }

  /** 由真实设备集合生成目标状态快照（配置数据，不是执行结果）。 */
  static buildTargetStates(
    devices: Device[],
    sceneType: SceneType,
    now: number
  ): DeviceStateSnapshot[] {
    const result: DeviceStateSnapshot[] = [];
    for (let i = 0; i < devices.length; i++) {
      const device: Device = devices[i];
      const snapshot: DeviceStateSnapshot = {
        deviceId: device.id,
        powerOn: MockDataFactory.targetPower(device.type, sceneType),
        params: DeviceParamsFactory.defaults(device.type),
        locked: MockDataFactory.targetLocked(sceneType),
        online: true,
        status: DeviceStatus.IDLE,
        capturedAt: now
      };
      result.push(snapshot);
    }
    return result;
  }

  /** 场景目标电源状态（纯函数，可单测）。 */
  static targetPower(type: DeviceType, sceneType: SceneType): boolean {
    if (sceneType === SceneType.AWAY || sceneType === SceneType.SLEEP) {
      return type === DeviceType.AIR_CONDITIONER && sceneType === SceneType.SLEEP;
    }
    if (sceneType === SceneType.STUDY) {
      return type !== DeviceType.FAN;
    }
    return type !== DeviceType.CURTAIN;
  }

  /** 场景目标门锁状态（纯函数）。 */
  static targetLocked(sceneType: SceneType): boolean {
    return sceneType !== SceneType.RETURN;
  }
}
