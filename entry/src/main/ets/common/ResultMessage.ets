/**
 * 智寓 · ResultCode → 简体中文提示唯一来源（设计 3.9 / 8.4）
 * 任何 UI 反馈必须取自本表，禁止在页面/组件中硬编码结果提示文案。
 */
export const RESULT_MESSAGE: Record<string, string> = {
  OK: '操作成功',
  NO_CHANGE: '状态未变化，无需重复操作',
  NOT_FOUND: '设备或规则不存在',
  INVALID_PARAM: '参数超出合法范围或类型不符',
  DEVICE_OFFLINE: '设备离线或故障，无法控制',
  CONFLICT_SKIPPED: '同轮已有更高优先级规则写入该参数，本次动作已跳过',
  STORAGE_ERROR: '数据保存失败，已降级处理',
  UNKNOWN: '发生未知错误，已记录日志'
};

/** 阶段二接口占位的统一后缀说明，避免占位被误读为「已经真实执行」。 */
export const STAGE2_PLACEHOLDER_HINT: string =
  '阶段二接口占位，业务逻辑将在阶段三接入';

/** 取结果码对应的中文提示；未登记码返回通用提示，不返回 undefined。 */
export function messageOf(code: string): string {
  const text: string = RESULT_MESSAGE[code];
  if (typeof text !== 'string' || text.length === 0) {
    return RESULT_MESSAGE['UNKNOWN'];
  }
  return text;
}

/** 阶段二占位场景的中文提示（原因码 + 占位说明）。 */
export function stage2Message(code: string): string {
  return messageOf(code) + '（' + STAGE2_PLACEHOLDER_HINT + '）';
}
