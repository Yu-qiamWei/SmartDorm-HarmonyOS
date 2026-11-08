/**
 * 智寓 · CommandResult<T> 统一命令结果（PRD 8.5 / 设计 3.9 / 4.2 失败语义）
 *
 * 所有 Service 写方法返回 CommandResult<T>；NO_CHANGE 也是 success=true（幂等成功）。
 * 本文件同时提供阶段二接口占位与阶段三实现共用的构造纯函数（无系统 API 依赖，
 * 可在 Node 侧单测）。中文提示唯一来源为 common/ResultMessage.ets 的 RESULT_MESSAGE。
 */
import { ResultCode } from './Enums';
import { RESULT_MESSAGE } from '../common/ResultMessage';

export interface CommandResult<T> {
  success: boolean; // 是否成功执行
  changed: boolean; // 是否产生真实状态变更（幂等判断 FR-02-08）
  code: ResultCode;
  message: string; // 面向用户的简体中文提示
  data?: T; // 成功时返回的对象
  timestamp: number; // 结果产生时间
}

/** 依据 ResultCode 推导 success / changed，并取唯一中文提示源。 */
export function createResult<T>(
  code: ResultCode,
  changed: boolean,
  data?: T,
  messageSuffix?: string
): CommandResult<T> {
  const success: boolean =
    code === ResultCode.OK || code === ResultCode.NO_CHANGE;
  const base: string = RESULT_MESSAGE[code];
  const message: string =
    messageSuffix === undefined || messageSuffix === ''
      ? base
      : base + '（' + messageSuffix + '）';
  const result: CommandResult<T> = {
    success: success,
    changed: changed,
    code: code,
    message: message,
    timestamp: Date.now()
  };
  if (data !== undefined) {
    result.data = data;
  }
  return result;
}

/** 成功且状态真实改变。 */
export function okResult<T>(data?: T, suffix?: string): CommandResult<T> {
  return createResult<T>(ResultCode.OK, true, data, suffix);
}

/** 幂等成功：状态未变化，不写业务日志（FR-02-08）。 */
export function noChangeResult<T>(data?: T, suffix?: string): CommandResult<T> {
  return createResult<T>(ResultCode.NO_CHANGE, false, data, suffix);
}

/** 失败：必须带明确原因码，绝不静默。 */
export function failResult<T>(code: ResultCode, suffix?: string): CommandResult<T> {
  return createResult<T>(code, false, undefined, suffix);
}
