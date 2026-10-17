import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/planner.dart';

/// Direct public-source lookup, not an arbitrary web search or a health-data API.
class AuthoritySourcesService {
  static const sources = <String, String>{
    'https://www.nhlbi.nih.gov/health/dash-eating-plan': 'NIH NHLBI · DASH',
    'https://wjw.hubei.gov.cn/bmdt/jkhb/spyy/202205/t20220520_4135821.shtml':
        '湖北省卫健委 · 中国居民膳食指南2022',
  };
  final http.Client Function() clientFactory;
  AuthoritySourcesService({http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? http.Client.new;
  Future<List<Json>> fetch() => Future.wait(
    sources.entries.map((entry) async {
      final client = clientFactory();
      try {
        return await (() async {
          final request = http.Request('GET', Uri.parse(entry.key))
            ..followRedirects = false;
          final response = await client.send(request);
          if (response.statusCode != 200) throw const PlanRejected('权威网站暂不可用');
          final bytes = <int>[];
          await for (final chunk in response.stream) {
            if (bytes.length + chunk.length > 600000) {
              throw const PlanRejected('来源页面超过大小限制');
            }
            bytes.addAll(chunk);
          }
          var html = utf8.decode(bytes, allowMalformed: true);
          html = html.replaceAll(
            RegExp(
              r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
              caseSensitive: false,
            ),
            ' ',
          );
          String clean(String value) => value
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll('&nbsp;', ' ')
              .replaceAll('&amp;', '&')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final paragraphs =
              RegExp(
                    r'<(?:p|li)\b[^>]*>([\s\S]*?)</(?:p|li)>',
                    caseSensitive: false,
                  )
                  .allMatches(html)
                  .map((m) => clean(m.group(1)!))
                  .where(
                    (p) =>
                        p.length > 30 &&
                        RegExp(
                          r'DASH|sodium|vegetables|whole grains|食盐|烹调油|膳食指南',
                          caseSensitive: false,
                        ).hasMatch(p),
                  )
                  .take(6)
                  .toList();
          final text = paragraphs.join('\n');
          if (text.isEmpty) throw const PlanRejected('未能核对来源正文');
          return <String, dynamic>{
            'url': entry.key,
            'title': entry.value,
            'retrieved_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'verified',
            'excerpt': text.substring(
              0,
              text.length > 1800 ? 1800 : text.length,
            ),
          };
        })().timeout(const Duration(seconds: 18));
      } catch (_) {
        return <String, dynamic>{
          'url': entry.key,
          'title': entry.value,
          'retrieved_at': DateTime.now().toUtc().toIso8601String(),
          'status': 'unavailable',
          'excerpt': '查询失败；继续使用本地固化规则，不声称联网成功。',
        };
      } finally {
        client.close();
      }
    }),
  );
}
