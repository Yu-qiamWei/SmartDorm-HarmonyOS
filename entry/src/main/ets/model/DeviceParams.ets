/**
 * 智寓 · DeviceParams 判别联合（DM-01 关联 / SC-01）
 *
 * ArkTS 严格类型红线 AT-04：访问联合属性前必须用 kind 收窄（switch）。
 * DeviceService.validate() 必须校验 params.kind === device.type，不一致返回 INVALID_PARAM。
 * 依据：design/系统架构设计.md 3.3 节、3.14 节常量范围。
 */
import { DeviceType, ACMode, ParamKey } from './Enums';

export interface LightParams {
  kind: DeviceType.LIGHT;
  brightness: number; // 0—100，整数，%
}

export interface AirConditionerParams {
  kind: DeviceType.AIR_CONDITIONER;
  temperature: number; // 16—30，整数，℃
  mode: ACMode;
}

export interface CurtainParams {
  kind: DeviceType.CURTAIN;
  openPercent: number; // 0—100，整数，%
}

export interface DoorLockParams {
  kind: DeviceType.DOOR_LOCK;
  locked: boolean; // true=上锁
}

export interface FanParams {
  kind: DeviceType.FAN;
  fanSpeed: number; // 1—3，整数
}

export interface SocketParams {
  kind: DeviceType.SOCKET;
  powerWatt: number; // 0—2500，W
}

export type DeviceParams =
  | LightParams
  | AirConditionerParams
  | CurtainParams
  | DoorLockParams
  | FanParams
  | SocketParams;

export type ParamValue = number | boolean | ACMode;

/** 设备参数默认值与可用参数键工厂（纯函数，可 Node 侧单测）。 */
export class DeviceParamsFactory {
  /** 按设备类型返回该类型的默认参数对象，kind 与 type 严格一致。 */
  static defaults(type: DeviceType): DeviceParams {
    switch (type) {
      case DeviceType.LIGHT:
        return { kind: DeviceType.LIGHT, brightness: 60 };
      case DeviceType.AIR_CONDITIONER:
        return { kind: DeviceType.AIR_CONDITIONER, temperature: 26, mode: ACMode.AUTO };
      case DeviceType.CURTAIN:
        return { kind: DeviceType.CURTAIN, openPercent: 0 };
      case DeviceType.DOOR_LOCK:
        return { kind: DeviceType.DOOR_LOCK, locked: true };
      case DeviceType.FAN:
        return { kind: DeviceType.FAN, fanSpeed: 1 };
      case DeviceType.SOCKET:
        return { kind: DeviceType.SOCKET, powerWatt: 0 };
      default:
        return { kind: DeviceType.LIGHT, brightness: 60 };
    }
  }

  /** 返回该设备类型可写的强类型参数键，供 ParamSchema 与 ST-03 WriteGuard 使用。 */
  static paramKeysOf(type: DeviceType): ParamKey[] {
    switch (type) {
      case DeviceType.LIGHT:
        return [ParamKey.BRIGHTNESS];
      case DeviceType.AIR_CONDITIONER:
        return [ParamKey.TEMPERATURE, ParamKey.MODE];
      case DeviceType.CURTAIN:
        return [ParamKey.OPEN_PERCENT];
      case DeviceType.DOOR_LOCK:
        return [ParamKey.LOCKED];
      case DeviceType.FAN:
        return [ParamKey.FAN_SPEED];
      case DeviceType.SOCKET:
        return [ParamKey.POWER_WATT];
      default:
        return [];
    }
  }

  /** 参数摘要的可读描述（页面卡片渲染，判别收窄后访问，AT-04）。 */
  static describe(params: DeviceParams): string {
    switch (params.kind) {
      case DeviceType.LIGHT:
        return '亮度 ' + params.brightness + '%';
      case DeviceType.AIR_CONDITIONER:
        return params.temperature + '℃ · ' + params.mode;
      case DeviceType.CURTAIN:
        return '开合 ' + params.openPercent + '%';
      case DeviceType.DOOR_LOCK:
        return params.locked ? '已上锁' : '已解锁';
      case DeviceType.FAN:
        return params.fanSpeed + ' 档';
      case DeviceType.SOCKET:
        return params.powerWatt + ' W';
      default:
        return '未知参数';
    }
  }
}
