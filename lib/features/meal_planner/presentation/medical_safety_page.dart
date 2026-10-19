import 'package:flutter/material.dart';
import '../data/planner_repository.dart';
import '../domain/medical_safety_screen.dart';
import '../domain/planner.dart';

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('健康风险核对')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('为高血压或肥胖家人使用前请逐项确认',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          '仅用于判断是否适合本 APP 的普通减重参考餐单，不是医生诊断。'
          '任何一项“有”或“不确定”，请先找医生或临床营养师核实；'
          '历史记录会保留。',
        ),
        const SizedBox(height: 14),
        for (final entry in MedicalSafetyScreen.labels.entries) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.value, style: const TextStyle(fontSize: 17)),
                  const SizedBox(height: 8),
                  Semantics(
                    identifier: 'planner-risk-${entry.key}',
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
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(feedback!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
