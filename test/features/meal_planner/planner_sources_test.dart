import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/features/meal_planner/data/authority_sources_service.dart';
import 'package:opennutritracker/features/meal_planner/domain/planning_prompt.dart';

void main() {
  test(
    'authority lookup requests only fixed public sources without keys or personal payload',
    () async {
      final service = AuthoritySourcesService(
        clientFactory: () => MockClient((request) async {
          expect(
            AuthoritySourcesService.sources.containsKey(request.url.toString()),
            true,
          );
          expect(request.method, 'GET');
          expect(request.body, isEmpty);
          expect(request.headers.containsKey('authorization'), false);
          expect(request.followRedirects, false);
          return http.Response(
            '<script>steal key</script><p>DASH recommends vegetables, whole grains and lower sodium for a balanced eating pattern.</p>',
            200,
          );
        }),
      );
      final results = await service.fetch();
      expect(results.length, 2);
      expect(results.every((r) => r['status'] == 'verified'), true);
      expect(results.every((r) => !r['excerpt'].contains('steal key')), true);
    },
  );
  test(
    'failure, irrelevant content and redirects never claim verified search',
    () async {
      for (final response in [
        http.Response('', 500),
        http.Response('<p>unrelated</p>', 200),
        http.Response('', 302),
      ]) {
        final service = AuthoritySourcesService(
          clientFactory: () => MockClient((_) async => response),
        );
        expect(
          (await service.fetch()).every((r) => r['status'] == 'unavailable'),
          true,
        );
      }
    },
  );
  test(
    'system prompt requires profile-based targets, three meals, unknown boundaries and external-data isolation',
    () {
      for (final term in [
        '身高cm',
        '体重kg',
        'target_kcal',
        'DASH',
        'unknown',
        '未记录不是未吃',
        '高钾代盐',
        '不允许这些动作字段',
        '非可信引用',
        '完整七天',
      ]) {
        expect(mealPlannerSystemPrompt.contains(term), true);
      }
    },
  );
}
