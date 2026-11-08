/**
 * 智寓 · 规则动作执行器（护栏 B-2 / B-4 / MI-12 步骤③）
 *
 * 单动作执行三段式（顺序**不得调换**）：
 *   ① `paramKey = commandToParamKey(action.command)`　—— B-4 唯一映射，无第二份映射表
 *   ② `guard.claim(targetDeviceId, paramKey, ruleId)`
 *        false → 立即返回 `ActionOutcome{ code: CONFLICT_SKIPPED }`，
 *                 **绝不调用 `DeviceService`**（B-2：先改设备再登记冲突等于冲突检测失效）
 *        true  → 继续
 *   ③ 按 `command` 分派到 `DeviceService.setPower / setParam`（actor=RULE）
 *
 * ★ `guard.claim()` 与设备调用之间**没有**其它可能返回的语句，保证「申请即执行」原子语义。
 * ★ 本类只处理 12 类命令中的设备控制子集；`SET_MODE` 等参数型命令统一走 `setParam`，
 *   由 `DeviceService` 的四步校验链负责范围与类型判定（不在此处重复校验，避免双份口径）。
 *
 * 依据：design/系统架构设计.md 4.4（护栏 B-1~B-7）、4.1 MI-12，Q-10。
 */
import { IDeviceService, commandToParamKey } from './ServiceContracts';
import { WriteGuard } from './WriteGuard';
import { AutomationAction } from '../model/AutomationAction';
import { ActionOutcome } from '../model/Reports';
import { Device } from '../model/Device';
import { CommandResult, failResult } from '../model/CommandResult';
import { DeviceCommand, ParamKey, ResultCode, LogActor, ACMode } from '../model/Enums';
import { messageOf } from '../common/ResultMessage';

export class RuleActionExecutor {
  private deviceService: IDeviceService;

  constructor(deviceService: IDeviceService) {
    this.deviceService = deviceService;
  }

  /**
   * 执行单个动作，返回带明确结果码的 `ActionOutcome`（永不抛异常给调用方）。
   * 冲突跳过时 `code = ResultCode.CONFLICT_SKIPPED`（命令结果码），
   * 由调用方汇总成 `RuleExecStatus.SKIPPED_CONFLICT`（日志状态码）——两者不得混用。
   */
  async execute(
    action: AutomationAction,
    guard: WriteGuard,
    ruleId: string
  ): Promise<ActionOutcome> {
    // ① B-4 唯一映射
    const paramKey: string = commandToParamKey(action.command);
    // ② 先 claim，后执行（B-2）
    const claimed: boolean = guard.claim(action.targetDeviceId, paramKey, ruleId);
    if (!claimed) {
      return this.conflictOutcome(action, paramKey);
    }
    // ③ claim 成功后才允许触碰设备
    const result: CommandResult<Device> = await this.applyCommand(action);
    return this.outcomeOf(action, paramKey, result);
  }

  /**
   * 命令分派。**唯一调用点在 `execute()` 内、`guard.claim()` 返回 true 之后**，
   * 因此本文件不存在绕过冲突登记的设备写入路径。
   */
  private async applyCommand(action: AutomationAction): Promise<CommandResult<Device>> {
    const deviceId: string = action.targetDeviceId;
    switch (action.command) {
      case DeviceCommand.POWER_ON:
      case DeviceCommand.SOCKET_ON:
        return this.deviceService.setPower(deviceId, true, LogActor.RULE);
      case DeviceCommand.POWER_OFF:
      case DeviceCommand.SOCKET_OFF:
        return this.deviceService.setPower(deviceId, false, LogActor.RULE);
      case DeviceCommand.SET_BRIGHTNESS:
        return this.deviceService.setParam(
          deviceId, ParamKey.BRIGHTNESS, action.value as number, LogActor.RULE
        );
      case DeviceCommand.SET_TEMPERATURE:
        return this.deviceService.setParam(
          deviceId, ParamKey.TEMPERATURE, action.value as number, LogActor.RULE
        );
      case DeviceCommand.SET_MODE:
        return this.deviceService.setParam(
          deviceId, ParamKey.MODE, action.value as ACMode, LogActor.RULE
        );
      case DeviceCommand.SET_OPEN_PERCENT:
        return this.deviceService.setParam(
          deviceId, ParamKey.OPEN_PERCENT, action.value as number, LogActor.RULE
        );
      case DeviceCommand.LOCK:
        return this.deviceService.setParam(deviceId, ParamKey.LOCKED, true, LogActor.RULE);
      case DeviceCommand.UNLOCK:
        return this.deviceService.setParam(deviceId, ParamKey.LOCKED, false, LogActor.RULE);
      case DeviceCommand.SET_FAN_SPEED:
        return this.deviceService.setParam(
          deviceId, ParamKey.FAN_SPEED, action.value as number, LogActor.RULE
        );
      case DeviceCommand.SET_POWER:
        return this.deviceService.setParam(
          deviceId, ParamKey.POWER_WATT, action.value as number, LogActor.RULE
        );
      default:
        return failResult<Device>(ResultCode.UNKNOWN, '未支持的设备命令：' + action.command);
    }
  }

  /** 冲突跳过结果：不触碰设备，只回报原因（同参数已由先执行者占用）。 */
  private conflictOutcome(action: AutomationAction, paramKey: string): ActionOutcome {
    const outcome: ActionOutcome = {
      actionId: action.id,
      deviceId: action.targetDeviceId,
      command: action.command,
      paramKey: paramKey,
      code: ResultCode.CONFLICT_SKIPPED,
      message: messageOf(ResultCode.CONFLICT_SKIPPED)
    };
    return outcome;
  }

  /** 把命令结果翻译成动作结果（透传真实 ResultCode，绝不私自改写为 OK）。 */
  private outcomeOf(
    action: AutomationAction,
    paramKey: string,
    result: CommandResult<Device>
  ): ActionOutcome {
    const outcome: ActionOutcome = {
      actionId: action.id,
      deviceId: action.targetDeviceId,
      command: action.command,
      paramKey: paramKey,
      code: result.code,
      message: result.message
    };
    return outcome;
  }
}
