import 'planning_prompt.dart';

/// Task-specific instructions layered over permanent safety and schema rules.
/// This is ONE bounded planning request, not several arbitrary LLM agents.
const firstWeekTaskPrompt = '''
【当前任务：首次建立饮食计划】
从使用者目前身高、体重、年龄、活动量、偏好和健康筛查状态出发，只生成首次七天参考菜单。
起始周重视熟悉家常食物、合理主食与三餐饱腹感；严格依照程序给定的渐进能量阶段。
不凭空假定已经减重、吃过哪些食物或已经适应节食。
''';

const followingWeekTaskPrompt = '''
【当前任务：安排下一周】
只根据有证据的实际饮食、饥饿反馈、已确认的忌口及长期偏好改善下一周七天菜单。
真实日记记录是观察事实；没有打卡不能推断没吃，体重波动不代表肌肉改变。
前一周没吃饱时按程序目标保持温和，不靠固定日期继续减少饭量。轮换允许食材，控制成本。
''';

const remainingMealsTaskPrompt = '''
【当前任务：仅调整尚未执行的部分】
current_plan 是本周目前版本。historical_locked_meals 表示不可更改的已吃、既往或已记录餐次。
锁定餐次必须逐字段不变；未执行餐次才允许更换，不能借机重新减小已固定的能量目标。
历史版本仅供验证哪些餐已记录，未完成的菜式可按忌口和便利性修改。
''';

const policyRefreshTaskPrompt = '''
【当前任务：重大策略升级后重建新版七天餐单】
这不是优化旧菜单，也不是照抄旧版推荐：仅使用新版本的身体资料、风险门禁、当前忌口、
食谱库和程序已经计算的渐进能量上下限，从零安排未来七天。
旧版 AI 菜式、旧热量目标和未被实际吃过的安排一律不作为参考。
过去已吃的客观记录由本地日志保留，不应通过生成新计划改写，不要要求删除历史。
新周每天都应均衡、足量，不能从第一天就快速削减饭量。
''';

const validationRepairTaskPrompt = '''
【当前任务：修正被本地校验拒绝的 JSON】
根据随后用户消息中给出的确切日期及校验失败原因，重新输出完整七天 JSON。
仅修复数值、菜谱 ID、份量或格式错误，不改变医学风险边界、忌口和已锁定历史餐次。
不要输出解释性文本、附加字段或无法核对的营养结论。
''';

String planningSystemPromptForMode(String mode) {
  final task = switch (mode) {
    'initial' => firstWeekTaskPrompt,
    'next_week' => followingWeekTaskPrompt,
    'adjust_remaining' => remainingMealsTaskPrompt,
    'policy_refresh' => policyRefreshTaskPrompt,
    _ => throw ArgumentError.value(mode, 'mode', 'Unknown planning mode'),
  };
  return [
    clinicalSafetyPrompt,
    verifiedMenuSelectionPrompt,
    if (mode != 'policy_refresh') observedHistoryContinuityPrompt,
    task,
    exactPlanJsonContractPrompt,
  ].join('\n\n');
}

String planningRepairPrompt(String reason) =>
    '$validationRepairTaskPrompt\n'
    '本地验证失败：$reason。请返回修正后的完整7天JSON。';
