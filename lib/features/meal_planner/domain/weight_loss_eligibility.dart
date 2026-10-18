import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';

/// Conservative scope of this family weight-loss planner, not a diagnosis.
String? weightLossIssue(UserEntity user) {
  if (!user.heightCM.isFinite ||
      !user.weightKG.isFinite ||
      user.age < 18 ||
      user.age > 90 ||
      user.heightCM < 130 ||
      user.heightCM > 220 ||
      user.weightKG < 40 ||
      user.weightKG > 200) {
    return '当前身体资料需要个体评估，暂不生成减重计划。';
  }
  final bmi = user.weightKG / (user.heightCM / 100) / (user.heightCM / 100);
  if (bmi < 18.5) {
    return '当前资料显示体重偏低，不适合减重。已暂停减重目标和计划执行。';
  }
  if (user.goal != UserWeightGoalEntity.loseWeight) {
    return '当前目标为维持或增重，已暂停减重目标和计划执行。';
  }
  if (user.age >= 80) {
    return '高龄人群需要先评估营养、肌力和疾病状况，暂不自动生成减重计划。';
  }
  if (user.age >= 60 && bmi < 28) {
    return '老年人不宜仅因超重自动节食；本模块面向肥胖人群，请先确认是否需要减重。';
  }
  if (bmi < 24) {
    return '当前 BMI 未达到本减重模块的超重适用范围，暂不生成减重计划。';
  }
  final goal = user.targetWeightKg;
  if (goal != null &&
      (!goal.isFinite ||
          goal / (user.heightCM / 100) / (user.heightCM / 100) <
              (user.age >= 60 ? 20 : 18.5))) {
    return '目标体重超出适用范围，请先评估，暂不生成减重计划。';
  }
  return null;
}
