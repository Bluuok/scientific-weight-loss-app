# 安卓科学减重与饮食打卡：本地二开说明

这是基于 OpenNutriTracker 的个人安卓分支，保留原应用及 GPL-3.0 版权、许可证和第三方声明。没有新增服务器、账号、云同步或多 Agent 系统。

- 实际项目：`E:\zzzz\OpenNutriTracker`
- 上游：<https://github.com/simonoppowa/OpenNutriTracker>
- 基线 commit：`8d2420f0305c96a4f798f3a111509827260f6df7`
- 本地分支：`codex/ai-weekly-weight-loss-plan`
- SDK：`.fvmrc` 固定 Flutter **3.44.6**，实际使用 Dart **3.12.2**；SDK 位于本项目 `.tools/flutter`。没有改系统 PATH。
- 只开发、测试和交付 Android；保留的上游 iOS 等文件没有扩展为本轮交付目标。安卓最低版本沿用上游 Android 8.0 / API 26。
- 未提交 Git commit、未推送、未创建 PR。

## 使用

1. 安装本次 Debug APK 后，完成原应用的首次资料设置：确认男性、约60岁、178cm、100kg及真实活动量；这些数值没有被强制覆盖到个人资料。
2. 首页点 **「我的计划」**。首次生成确认高血压安全提示；第一次真实 AI 规划还会说明资料发送目的地，需要主动同意。
3. 点 **「生成未来7天计划」**，选择开始日期；每天有早餐、午餐、晚餐和饮食回顾，默认午餐是简洁餐。
4. 点日期查看食材克数、生重/干重、做法、油盐和来源。点击「一键完成」关联原日记；可以撤销、调整实际份量、明确未吃。
5. 「吃了别的」打开原食物录入页。实际录入后回到当天计划，关联真实记录、移除这餐的计划记账，防止两边重复统计。撤销计划状态不会删除用户手工录入的真实日记。已有替换记录时，重新按计划记账会要求先核对日记。
6. 「换一道计划餐」只允许今天或未来未记录的餐，整周复算通过才保存新版本；原日记中已经记录的餐也会锁定。
7. 饮食回顾写一句即可；体重按钮打开原应用体重历史，可以录入体重。设置页可选忌口、简洁餐时段、快手、省钱、口味偏好。
8. 下一周读取此前14天真实日记、计划执行状态和体重；没有体重历史就不推断趋势。调整本周保留过去日期、已记录事项及真实日记，保留旧版本。

## 持久密钥与 API

按用户授权，密钥已写入本地私有 **`.env`** 的 `PLANNER_API_KEY`，通过项目既有 Envied 混淆生成的 **`lib/core/utils/env.g.dart`** 接入。两者均被 Git 忽略；公开源码和本说明不含真实密钥。此个人 APK 可直接使用默认配置，不必每次打开重新填写。

默认 `https://api.deepseek.com`、模型 `deepseek-flash`、接口 `/chat/completions`。内置私有默认密钥只对 DeepSeek 官方默认地址生效；自定义服务请自行填写对应密钥。更换地址需要重新同意资料发送。设置界面不会回显密钥；「清除密钥」会持久禁用该安装中的默认密钥，切换到备用模板。

如以后换 Key：修改私有 `.env`，运行代码生成再构建；也可在手机「我的计划 → 设置」保存新 Key 到 Android 安全存储，优先于编译默认值。

```powershell
Set-Location E:\zzzz\OpenNutriTracker
$env:PUB_CACHE="$PWD\.tools\pub-cache"
.\.tools\flutter\bin\flutter.bat pub get
.\.tools\flutter\bin\flutter.bat gen-l10n
.\.tools\flutter\bin\dart.bat run build_runner build
.\run_android.ps1 build
# 已连接安卓设备时：
.\run_android.ps1 run
```

无真实 Key 时可以使用明确标识的备用模板；自动测试也覆盖 Mock 路径。AI、Mock 和备用模板共用 `PlanRules`，没有绕过营养校验的写库通道。错误时保留原计划；未知食谱、缺失数据、结构错误或营养不合格的计划不会发布。

API 超时60秒；结构/营养错误最多修复2次。网络/鉴权/限流失败不循环请求。响应大小有上限，拒绝重定向；取消不会偷偷保存备用计划。不会把服务端错误正文、密钥或请求健康资料写入日志。

## 营养来源与边界

本地库有 **26种基础食材、13种完整食谱**，来自 USDA 官方 SR Legacy 2018 CSV。`assets/meal_planner/catalog.json` 保存 FDC ID、原始描述、每100g可食部的营养、原料状态、来源 URL、原始压缩包 SHA-256。中文名称是本分支显示名称；例如豆腐明确对应钙凝固硬豆腐，不能把其他豆腐规格当成相同数据。

数据提取脚本：`tool/meal_planner/extract_usda_catalog.py`。原始官方地址：<https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip>。需自行把下载文件放到 `.local/usda.zip` 才可重新提取。

程序复算食物、普通食盐及全部烹调油，独立检查日期、三餐、每日恰好一顿简洁餐、食谱 ID、份量、忌口、食物组、周多样性、能量、蛋白质、钠与油。示范个人资料复用上游 IOM2005 估算维持消耗，取约10%温和缺口；最低1800kcal，超出支持范围则拒绝自动规划。蛋白质参考下限按体重估算并设保守范围，全天蛋白质不超过150g。此处均是工程参考边界，不是已完成临床评估的个人处方。

- 规则版本：`cn2022-dash-reference-v2`
- 全天钠≤2000mg，食盐当量≈钠mg×2.5/1000；全天烹调油≤30g。
- [中国居民膳食指南2022少盐少油建议（湖北省卫健委转载）](https://wjw.hubei.gov.cn/bmdt/jkhb/spyy/202205/t20220520_4135821.shtml)
- [NIH NHLBI DASH](https://www.nhlbi.nih.gov/health/dash-eating-plan)

计划是原料生重/干重估算，真实食物、烹调水分和损耗会有差异；界面不会把估算叫作精确医学结论。不提供钾补充剂、高钾代盐、调药、断食或强运动训练建议。父亲持续服药但血压控制不佳，需要复诊；软件不替代医生。

## 实现范围

- `lib/features/meal_planner/domain/planner.dart`：日历日期、营养复算、严格 schema 和硬规则、备用模板、剩余计划合并。
- `lib/features/meal_planner/data/meal_planning_service.dart`：私有配置、安全存储、DeepSeek 兼容 HTTP、超时/取消/有限修复。
- `lib/features/meal_planner/data/planner_repository.dart`：原用户/日记/体重接口、历史摘要、计划版本、幂等打卡、替换日记关联与中断恢复。
- `lib/features/meal_planner/presentation/`：周总览、每日详情、偏好/API设置、只读版本历史；使用原 Material 样式和 Semantics。
- `lib/core/utils/hive_db_provider.dart`：新增随 profile 生命周期打开/关闭/删除的 **AES加密 `Box<String>`**，以版本化 JSON 保存完整状态，不增加 Hive typeId 或手改适配器。
- `lib/core/utils/locator.dart`：沿用 get_it 注册。
- `lib/core/presentation/main_screen.dart`：首页入口和返回后刷新原日记/主页。
- `lib/core/utils/navigation_options.dart`、`lib/features/meal_detail/presentation/widgets/meal_detail_bottom_sheet.dart`：食物录入后可返回当天计划，原首页路径继续保留。
- `lib/core/utils/env.dart`、`.env.example`：可选私有规划 Key；原识别 AI 接口未更改。
- `pubspec.yaml`：只增加本地食材库 asset，没有新依赖。
- `lib/l10n/intl_en.arb`、`intl_zh.arb`：仅增加新功能文案。此中文个人分支有意限定增加中文资源，区别于上游只在英文模板添加字符串、交给 Weblate 翻译的发布流程；未批量改其他语言。
- 新增7个 `test/features/meal_planner/` 测试文件和手动真实 API 测试 `tool/meal_planner_live_test.dart`。

## 验证记录

所有命令在实际 checkout 执行，日志在 `.local/`。真实 API 只通过明确的手动命令运行，不会混入全量测试自动产生费用。

| 检查 | 真实结果 |
| --- | --- |
| 原版 `flutter pub get`、`gen-l10n`、`dart run build_runner build` | 通过 |
| 原版 `flutter analyze` | 通过，0 issues |
| 原版 `flutter test` | 2591通过、1跳过、2失败；均为 `plaintext_destination_guard_test.dart` Windows zoned IPv6 URI 测试 |
| 原版 Debug APK尝试 | 当时未安装Android SDK，明确失败；随后本项目内补齐SDK |
| 新功能 `flutter test test/features/meal_planner` | 24项通过，包括多种恶意结构/营养输入、真实加密Hive重启、中断恢复、重复点击、撤销、替换日记、换餐版本和中文页面交互 |
| 最终全量 `flutter test` | 2616通过、2失败，与基线相同的2项；无新增回归失败 |
| 手动 `flutter test tool/meal_planner_live_test.dart` | 真实DeepSeek整周首次生成、调整剩余餐次、下一周3场景通过；提示先从整周示例改为单日schema，再补全中文科学减重系统提示，两次改进均再次真实通过3场景，调整包含排除牛肉硬校验 |
| 中文UI与大字号 | 实际Flutter Widget交互及1.4倍字体布局测试通过；截图位于 `outputs/planner-day-widget.png` |
| 真实Android设备 | `adb devices -l` 无设备；尚未真机/模拟器验收，不将Widget测试写成真机通过 |

真实API结果的匿名摘要：`outputs/真实API验收.json`。AI必须构造七天计划；提示只展示一天的 schema，避免照抄整周模板。验收同时复算营养和检查锁定事项。

重新运行：

```powershell
.\run_android.ps1 test
.\run_android.ps1 analyze
$env:PUB_CACHE="$PWD\.tools\pub-cache"
# 会真实调用DeepSeek并产生API费用：仅在用户授权后运行
.\.tools\flutter\bin\flutter.bat test tool/meal_planner_live_test.dart
```

## 使用限制

- 没有连接Android设备，设备安装、前后台切换、跨午夜和系统时区切换的真机行为尚未验收；日期边界和持久化已有自动测试。
- Supabase联网食品库仍是有效格式的离线占位配置，未声称该联网库已联调；本地规划库、已有自建食物及备用模板不依赖它。Open Food Facts仍沿用上游接口。
- 本地库较小；忌口导致无法搭配时会明确拒绝，不捏造营养数据。替换任意外部食物必须在原日记记录，不能将它当成本地已验证食谱。
- 本次计划/执行历史保存在本地加密盒子，但未扩展上游ZIP导出格式；上游ZIP导出不包含新增计划盒子。卸载或清除应用数据会删除本地历史。
- 联网查询采用直接读取 NIH DASH 和湖北省卫健委指南原文的轻量方式，两个来源已实际联网核对成功。设置页点击「联网查询权威饮食来源」，成功结果带URL、时间及节选，缓存24小时，后续规划输入会引用仍有效的资料。没有任意网页搜索或复杂搜索Agent；查询失败明确标识，不绕过本地营养规则。请求为公开GET，不发送个人健康数据或Key。

## 系统提示词与联网资料

完整中文系统提示词位于 `lib/features/meal_planner/domain/planning_prompt.dart`，明确读取当前身高、体重、年龄、活动量、健康边界和程序能量目标；要求温和减重、三餐均衡、每日一顿简洁餐、禁忌排除与真实历史续接，禁止补剂、改药、极端饮食等建议。严格schema和营养复算仍由程序独立执行。

`lib/features/meal_planner/data/authority_sources_service.dart` 只请求固定权威来源，限制响应大小、时间与重定向，网络文字只作为非可信引用，不能修改本地阈值。

真实联网检查命令：`flutter test tool/authority_sources_live_test.dart`，两个固定来源均返回已核对状态。

## 最终交付

- 安卓安装包：`outputs/科学减重-安卓.apk`（Debug个人测试版，内含持久私有配置；不要把这个带个人Key的安装包当公开发行包分享）。
- 安装方式：把APK传到自己的安卓手机，打开文件并按手机提示允许该安装来源；无需云账号。或连接开发设备后执行 `.tools/android-sdk/platform-tools/adb.exe install -r outputs/科学减重-安卓.apk`。
- 本机没有连接真机/模拟器。Flutter页面渲染、交互、持久化和真实网络已验证，实际手机安装及跨午夜/时区行为仍需设备验收。
- APK构建：`.\run_android.ps1 build`；真实命令为 `flutter build apk --debug --flavor develop`，已成功。Flutter工具和Android SDK/NDK/Gradle缓存均在项目 `.tools/`，未改系统PATH。
- 安装包原始路径：`build/app/outputs/flutter-apk/app-develop-debug.apk`。
- 最终静态分析、APK校验值、实际测试结果在 `outputs/交付验收.json`，详细运行日志保留在 `.local/`。

## 验收清单

- [x] 新克隆本地分支，基线与修改范围可追溯。
- [x] 我的计划入口、连续七天概览、每日三餐与回顾。
- [x] 食材克数、油盐、做法、原料状态及营养来源。
- [x] 打卡/撤销、真实份量、换餐、明确未吃与未记录区分；避免重复记账。
- [x] 每日恰好一顿简洁餐，整日和每周多样性校验。
- [x] 热量/钠/油/蛋白质独立复算，失败不发布。
- [x] 持久DeepSeek配置、真实API、兼容端点、备用模板与Mock测试。
- [x] 调整剩余餐次不覆盖历史，下一周读取实际历史。
- [x] 离线、超时、限流、错误JSON、非法ID、取消等异常测试。
- [x] 加密Hive真实关闭重开、状态与日记中断恢复测试。
- [x] 自动测试、静态分析与实际Android APK构建。
- [x] 本二开说明及实际产物。
- [ ] Android真机/模拟器安装、进程重启、跨午夜/系统时区切换验收（未连接设备）。


## 30天方向与相邻日期衔接更新

已根据 Eat This Much、MyFitnessPal、Noom 官方帮助和 NIH DASH 资料进一步完善系统提示词；调研与来源在 `outputs/调研与提示词设计.md`。

- 周总览展示个性化30天方向与当前阶段；框架携带当前身高、体重对应BMI、程序能量参考和蛋白质下限。先建立规律，再改善轮换和方便程度，最后复盘；不承诺一个月减到95kg。
- 仍每次只生成七天，前后周使用真实历史衔接。每日都基本均衡；不把昨天未记录解释为营养缺乏，不用跳餐或大量单一食物补偿。
- 有足够可行选择时，每周简洁餐至少轮换三类主蛋白，同一种不连续安排三天；该具体次数是本项目产品规则，不能冒称临床统一标准。
- 真实API测试包含当前月度框架、已经检索的权威来源和前两天吃鸡肉的已知历史，已验证下周第一顿简洁餐切换其他来源。
- 新增 `domain/monthly_direction.dart`、月度测试；完整提示词仍在 `domain/planning_prompt.dart`。新的计划版本保存月度框架快照。
- Google AI Studio 原生Android构建及USB/ADB安装功能已查官方说明；本项目没有上传Google，本机APK可以直接安装。

## 本轮性能检查与最终验证

- 周总览复用用户资料 Future，普通重绘不再重复读取；从日计划返回时主动刷新，避免体重显示过期。现有页面交互测试验证了这两种行为。
- 安全存储的四个独立配置字段并行读取，保留原有私有配置与目的地址隔离。
- 仅对官方 DeepSeek 的 deepseek-flash 使用低强度推理，保留思考和全部本地营养校验；兼容服务不发送供应商专用参数，已用请求测试验证。
- 真实 API 三种场景本轮生成耗时分别约 15.8、18.8、20.0 秒，共约 54.6 秒。上轮测试运行约 51 秒，本次未证明网络生成变快，不承诺固定等待时间。
- 最终专项测试25项通过；最新静态分析、完整回归、构建日志及安装包SHA256统一见 outputs/交付验收.json。原项目两项 IPv6 区域标识测试失败单独保留记录。
- 当前交付为个人测试版 APK，尚无手机连接，因此未测量手机启动时间、内存、帧率及电耗。

## AI 核心首页与简洁中文版

本轮按实际手机反馈调整：

- 打开应用默认进入“我的计划”，顶部突出智能生成与执行；主导航只保留我的计划、饮食记录、我的资料。
- 从主界面移除趋势入口，从简洁资料页移除断食、食谱库、每周速率、高级热量渐变及完整设置列表。原热量仪表盘保留为计划页的“饮食记录”快捷入口；历史数据、日记、体重、家人资料切换继续使用原底层能力。本轮没有宣称删除这些模块的全部源码。
- 个人分支固定中文；计划来源、营养数据库名称、失败提示及单位使用中文，不再展开英文原料描述和外文网页摘录。地址、密钥、模型标识为实际连接参数，保留原值。
- 真实资料如果体重偏低、目标为增重或维持，或未达到本减重模块的超重适用范围，不显示可执行的减重计划，也不生成新计划；从服务层禁止按旧减重计划新增打卡。旧计划与真实日记不删除。
- 首阶段约5%不是总减重上限；“目标体重”可以设置长期目标，传入月度框架和智能计划上下文。程序不自动反复加大热量缺口，也不承诺固定期限。
- 原版“AI辅助”是食物文字/照片识别，不是周计划生成；现在已支持通过其兼容接口配置 DeepSeek。仅官方 DeepSeek Flash 食物识别请求关闭思考模式，以兼容强制工具调用；科学计划推理和营养校验不变。
- 原版自定义地址的中文说明已修正为“兼容服务（云端或自建）”，不再把 DeepSeek 云服务误写成无第三方的自建服务器。
- 实际 DeepSeek 固定文字和随包示例食物照片均已通过；不发送手机相册或用户私人照片作为测试素材。

国人体重分类参考：https://www.nhc.gov.cn/xcs/c100122/202505/5163974755e044cfa3883afa80a1f4d0.shtml
DeepSeek 强制工具调用说明：https://api-docs.deepseek.com/zh-cn/api/create-chat-completion/
最新日志：.local/home-core-final.log、.local/native-deepseek-live.log、.local/home-analyze-final.log、.local/home-all-tests.log、.local/home-apk.log。

## 固定提示词与本地记忆核对
完整说明见 outputs/AI提示词与记忆说明.md。首次生成、剩余餐调整、下一周、格式修复以及原版文字/照片识别，每次发送固定规则的契约验证已通过；专项合计33项。业务代码与已覆盖安装的APK一致。本机真机检查确认默认AI首页、三个导航、原资料与密钥保留、低体重生成禁用、DeepSeek文字和照片探测通过。家人的实际计划需要建立家人资料后生成，未用当前低体重资料做减重执行测试。


## 2026-10-16 一个月流程复核
已使用隔离合成资料完成30天压缩模拟，真实DeepSeek最终11次逻辑生成均成功，88条模拟进食记录、零重复、五次数据库重开通过。新增历史餐次与新忌口兼容、简洁餐时段跨周一致性、请求期间资料变化保护。专项40项通过，完整回归2632项通过、两项原有IPv6测试失败，静态检查无问题；详细边界见 outputs/一个月流程验收.md。新版APK已构建，覆盖安装是否完成以最新真机验收为准。测试中的体重趋势为合成输入，不代表人体减重效果。

## 2026-10-16 老年人易用性复核

正文默认18，保留系统放大；首页优先今天餐单，次要操作收起，实际份量改为相对所示餐单的百分比。偏好固定底部保存、未保存离开提醒；首次设置减少服务参数；中文日期和简洁记录页、带文字的食物识别入口、简短身体资料摘要均已在手机核对。8项易用性交互、2项日历检查、完整回归2638项通过，保留2项原有IPv6失败；静态检查无问题。真实DeepSeek月度和食物接口已重跑。最终新版已覆盖安装，原真实资料保留。详细证据及未验证范围见 outputs/老年人易用性验收.md；未进行真实老人参与的可用性研究。
