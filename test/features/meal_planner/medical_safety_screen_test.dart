import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/medical_safety_screen.dart';

void main() {
  Json clear() => {
    for (final key in MedicalSafetyScreen.labels.keys) key: 'no',
  };
  test('missing, unknown and confirmed risks must not be auto-cleared', () {
    expect(MedicalSafetyScreen.issue(null), isNotNull);
    expect(
      () => MedicalSafetyScreen.normalize({'kidney_disease': 'no'}),
      throwsA(isA<PlanRejected>()),
    );
    for (final key in MedicalSafetyScreen.labels.keys) {
      final unknown = clear()..[key] = 'unknown';
      final known = clear()..[key] = 'yes';
      expect(MedicalSafetyScreen.issue(
          MedicalSafetyScreen.normalize(unknown)), isNotNull);
      expect(MedicalSafetyScreen.issue(
          MedicalSafetyScreen.normalize(known)), isNotNull);
    }
  });
  test('complete self-report permits reference plan, not medical clearance', () {
    final saved = MedicalSafetyScreen.normalize(clear());
    expect(MedicalSafetyScreen.issue(saved), isNull);
    expect(saved['version'], MedicalSafetyScreen.version);
    expect(saved['answers'].length, MedicalSafetyScreen.labels.length);
    expect(MedicalSafetyScreen.issue({
      ...saved, 'version': 'older-hypertension-risk-v0',
    }), isNotNull);
  });
}
