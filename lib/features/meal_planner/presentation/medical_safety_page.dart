import 'package:flutter/material.dart';
import '../data/planner_repository.dart';
import '../domain/medical_safety_screen.dart';
import '../domain/planner.dart';
import 'planner_visual.dart';

/// A short self-report, not a clinical diagnosis or clearance document.
class MedicalSafetyPage extends StatefulWidget {
  final PlannerRepository repo;
  const MedicalSafetyPage({super.key, required this.repo});
  @override
  State<MedicalSafetyPage> createState() => _MedicalSafetyPageState();
}

class _MedicalSafetyPageState extends State<MedicalSafetyPage> {
  late final Json answers;
  String? feedback;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final saved = widget.repo.state['medical_screen'];
    final values = saved is Map && saved['version'] == MedicalSafetyScreen.version
        && saved['answers'] is Map ? saved['answers'] as Map : const {};
    answers = {
      for (final key in MedicalSafetyScreen.labels.keys)
        key: ['no', 'yes', 'unknown'].contains(values[key])
            ? values[key] as String : 'unknown',
    };
  }

  Future<void> _save() async {
    setState(() { saving = true; feedback = null; });
    try {
      await widget.repo.saveMedicalScreen(answers);
      if (!mounted) return;
      final issue = widget.repo.medicalSafetyIssue;
      if (issue == null) {
        Navigator.pop(context, true);
      } else {
        setState(() => feedback = issue);
      }
    } catch (e) {
      if (mounted) setState(() => feedback = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = answers.values.where((v) => v != 'unknown').length;
    return Scaffold(
    backgroundColor: PlannerVisual.background,
    appBar: AppBar(title: const Text('健康风险核对')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: PlannerVisual.info,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('先确认这 7 件事',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: PlannerVisual.infoInk)),
                const SizedBox(height: 6),
                Text('已明确 $confirmed / 7 项 · 不清楚就保留“不确定”',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: PlannerVisual.infoInk)),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: confirmed / MedicalSafetyScreen.labels.length,
                  color: PlannerVisual.infoInk,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 8),
                Text('若有疾病风险或还不清楚，先向医生确认，不能直接生成减重菜谱。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: PlannerVisual.infoInk)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final entry in MedicalSafetyScreen.labels.entries) ...[
          Card(
            color: ['blood_pressure_uncontrolled', 'kidney_disease',
                    'potassium_medication_risk'].contains(entry.key)
                ? PlannerVisual.caution : Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${MedicalSafetyScreen.labels.keys.toList().indexOf(entry.key) + 1}. ${entry.value}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: PlannerVisual.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    identifier: "planner-risk-${entry.key.replaceAll('_', '-')}",
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'no', label: Text('没有')),
                        ButtonSegment(value: 'yes', label: Text('有')),
                        ButtonSegment(value: 'unknown', label: Text('不确定')),
                      ],
                      selected: {answers[entry.key]! as String},
                      onSelectionChanged: saving ? null : (values) =>
                          setState(() => answers[entry.key] = values.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (feedback != null)
          Semantics(
            liveRegion: true,
            child: Card(
              color: PlannerVisual.caution,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('需要先向医生或营养师确认',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: PlannerVisual.cautionInk)),
                    Text(feedback!,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: PlannerVisual.cautionInk)),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('返回我的计划'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Semantics(
          identifier: 'planner-save-risk-screen',
          child: FilledButton(
            onPressed: saving ? null : _save,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text('保存健康风险核对'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '即使全部选择“没有”，也不代表血压、肾功能已被检查正常。'
          '不能自行停药、调整限钾/限蛋白处方或加强运动强度。',
        ),
      ],
    ),
  );
  }
}
