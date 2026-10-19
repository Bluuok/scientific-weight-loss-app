# 30天执行反馈（2026-10-19）

每个周期为连续 30 天，四阶段分别覆盖 1–7、8–14、15–21、22–30 天（**最后阶段 9 天**）。
指标基于去重后的、截至当前日期实际存在计划的日期，仅统计三餐记录：

- `recorded_as_planned`：用户明确按计划完成记录；
- `recorded_replaced`：用户明确换成其他食物并关联真实日记；
- `explicitly_skipped`：用户明确标记没吃；
- `unknown_meals`：未记录，绝不能推断没吃；
- `recorded_fraction`：**记录覆盖率**，不是方案执行率、饮食达标率或者减脂成功率。

从上一周到下一周，系统已传真实日记、体重和菜式历史给 AI；本轮增补结构化四阶段统计供模型理解实际执行，但不能因某周未记或一次体重上涨自动减少能量目标。数据仍本地加密，只有经用户原有 AI 授权后才随生成请求传出。

现有 BMI 和体重变化无法证明“保肌”。未来可选记录血压、力量和身体活动能力，但不要把用户没记录的值补成正常。老年人需要把营养状态与功能变化一起看待。

指南依据：
- 2026 年老年肥胖管理共识：https://pmc.ncbi.nlm.nih.gov/articles/PMC13535939/
- NICE 定期体重、饮食与活动记录：https://www.nice.org.uk/guidance/ng246/chapter/Preventing-overweight-obesity-and-central-adiposity
