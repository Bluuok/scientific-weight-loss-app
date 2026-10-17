import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/add_meal/data/openai_compatible_meal_items_api.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_items_api.dart';

void main() {
  test(
    'DeepSeek forced food tools disable thinking only for official endpoint',
    () async {
      for (final host in [
        'https://api.deepseek.com',
        'https://example.invalid',
        'https://api.deepseek.com.evil.invalid',
      ]) {
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(body['tool_choice'], 'required');
          if (host == 'https://api.deepseek.com') {
            expect(body['thinking'], {'type': 'disabled'});
          } else {
            expect(body.containsKey('thinking'), false);
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'tool_calls',
                  'message': {
                    'tool_calls': [
                      {
                        'type': 'function',
                        'function': {
                          'name': 'log_meal_items',
                          'arguments': jsonEncode({
                            'items': [
                              {'query': '鸡蛋', 'quantity': 2},
                            ],
                          }),
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final api = OpenAiCompatibleMealItemsApi(
          client,
          () => 'test-only',
          model: 'deepseek-flash',
          endpoint: Uri.parse('$host/v1/chat/completions'),
          toolChoice: ToolChoiceMode.anyTool,
        );
        final result = await api.requestItems(
          content: const MealTextContent('两个鸡蛋'),
          system: 'Extract foods',
        );
        expect(result.items.length, 1);
      }
    },
  );
}
