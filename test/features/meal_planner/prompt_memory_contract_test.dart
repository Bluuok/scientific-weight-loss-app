import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/meal_planner/domain/planner.dart';
import 'package:opennutritracker/features/meal_planner/domain/planning_prompt.dart';
import 'package:opennutritracker/features/meal_planner/data/meal_planning_service.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_text_interpreter.dart';
import 'package:opennutritracker/features/add_meal/data/model_meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_text_parser.dart';
import 'planner_test.dart' show MemoryCredentials;

class CapturingFoodApi implements MealItemsApi {
  final systems = <String>[];
  @override
  Future<MealTextParseResult> requestItems({
    required MealContent content,
    required String system,
  }) async {
    systems.add(system);
    return const MealTextParseResult(
      items: [ParsedMealItem(query: '鸡蛋', quantity: 2)],
      errors: [],
    );
  }
}

void main() {
  test(
    'every plan mode and repair request includes permanent policy and current context',
    () async {
      final rules = PlanRules(
        FoodCatalog(
          jsonDecode(
                File('assets/meal_planner/catalog.json').readAsStringSync(),
              )
              as Json,
        ),
        targetKcal: 2337,
        minimumProtein: 80,
      );
      final sent = <Json>[];
      for (final mode in ['initial', 'adjust_remaining', 'next_week']) {
        var calls = 0;
        final date = mode == 'next_week' ? '2026-10-23' : '2026-10-16';
        final service = MealPlanningService(
          MemoryCredentials(),
          clientFactory: () => MockClient((request) async {
            sent.add(jsonDecode(request.body) as Json);
            calls++;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {
                      'content': mode == 'initial' && calls == 1
                          ? '{}'
                          : jsonEncode(rules.fallback(date)),
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );
        final result = await service.generate(rules, date, {
          'mode': mode,
          'monthly_direction': {'phase': 1},
          'history_summary': {
            'known_recent_proteins': ['chicken'],
          },
        });
        expect(result['source'], 'ai');
      }
      expect(sent.length, 4);
      for (final request in sent) {
        final messages = request['messages'] as List;
        expect(messages.first, {
          'role': 'system',
          'content': mealPlannerSystemPrompt,
        });
        final context = jsonDecode(messages[1]['content']);
        expect(context['monthly_direction']['phase'], 1);
        expect(context['history_summary']['known_recent_proteins'], [
          'chicken',
        ]);
      }
    },
  );
  test(
    'food text and photo recognition attach their own fixed policy every time',
    () async {
      final api = CapturingFoodApi();
      for (var i = 0; i < 2; i++) {
        await ModelMealTextInterpreter(api).interpret('两个鸡蛋', localeCode: 'zh');
        await ModelMealPhotoInterpreter(api).interpret(
          MealPhoto(bytes: Uint8List.fromList([1, 2]), mediaType: 'image/jpeg'),
          localeCode: 'zh',
        );
      }
      expect(api.systems.length, 4);
      expect(api.systems[0], api.systems[2]);
      expect(api.systems[1], api.systems[3]);
      expect(api.systems[0], isNot(api.systems[1]));
      expect(api.systems.every((s) => s.contains('zh')), true);
      expect(
        api.systems.every((s) => !s.contains(mealPlannerSystemPrompt)),
        true,
        reason:
            'Food recognition must not replace actual intake with a generated menu',
      );
    },
  );
}
