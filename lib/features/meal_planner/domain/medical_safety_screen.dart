import 'planner.dart';

/// User-reported triage only: a clear screen is not medical clearance.
class MedicalSafetyScreen {
  static const version = 'older-hypertension-risk-v1';
  static const labels = <String, String>{
    'blood_pressure_uncontrolled': '近期血压控制不佳、反复明显升高或医生提示未稳定',
    'kidney_disease': '已知肾病、透析、肾功能异常或医生要求特殊蛋白饮食',
    'potassium_medication_risk': '医生要求限制钾、使用低钠高钾代盐或药物需要监测血钾',
    'swallowing_difficulty': '吞咽呛咳、疑似误吸或需要特殊质地食物',
    'frailty_or_muscle_loss': '明显虚弱、肌力下降、近期反复跌倒或进食困难',
    'unintentional_weight_loss': '近期非自愿体重明显下降',
    'special_diet': '医生已开具其他必须遵守的特殊营养处方',
  };

  static Json normalize(Json answers) {
    if (answers.keys.toSet().difference(labels.keys.toSet()).isNotEmpty ||
        labels.keys.any((key) => !['no', 'yes', 'unknown'].contains(answers[key]))) {
      throw const PlanRejected('健康风险核对尚未完整填写');
    }
    return {
      'version': version,
      'answers': {
        for (final key in labels.keys) key: answers[key],
      },
    };
  }

  static String? issue(Object? saved) {
    if (saved is! Map || saved['version'] != version ||
        saved['answers'] is! Map) {
      return '生成减脂餐单前，请先完成健康风险核对。';
    }
    final answers = saved['answers'] as Map;
    for (final key in labels.keys) {
      final answer = answers[key];
      if (answer == 'yes') {
        return '核对中存在需要专业评估的风险：${labels[key]}。'
            '请先向医生/临床营养师确认适用方案，暂不自动生成减重餐单。';
      }
      if (answer != 'no') {
        return '健康风险核对尚有不确定项：${labels[key]}。'
            '请与家人或医生核实后再使用自动减脂计划。';
      }
    }
    return null;
  }
}
