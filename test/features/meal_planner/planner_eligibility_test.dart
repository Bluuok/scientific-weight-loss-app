import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/features/meal_planner/domain/weight_loss_eligibility.dart';
import 'planner_persistence_test.dart' show TestUser;

void main() {
  test('overweight family loss profile remains eligible', () async {
    expect(weightLossIssue(await TestUser().getUserData()), isNull);
  });
  test(
    'underweight and normal-weight profiles do not receive loss targets',
    () async {
      for (final weight in [55.0, 70.0]) {
        expect(
          weightLossIssue(await TestUser(weight: weight).getUserData()),
          isNotNull,
        );
      }
    },
  );
  test('gain and maintenance goals never use loss plans', () async {
    for (final goal in [
      UserWeightGoalEntity.gainWeight,
      UserWeightGoalEntity.maintainWeight,
    ]) {
      expect(
        weightLossIssue(await TestUser(goal: goal).getUserData()),
        isNotNull,
      );
    }
  });
}
