import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:apexlytics/models/news_article.dart';
import 'package:apexlytics/providers/api_provider.dart';
import 'package:apexlytics/providers/news_provider.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/services/news_service.dart';

class MockNewsService extends Mock implements NewsService {}

void main() {
  late ProviderContainer container;
  late MockNewsService mockNewsService;

  setUp(() {
    mockNewsService = MockNewsService();
    container = ProviderContainer(
      overrides: [
        newsServiceProvider.overrideWithValue(mockNewsService),
      ],
    );
  });

  group('NewsNotifier', () {
    test('returns pinned news when API returns empty list', () async {
      when(() => mockNewsService.getNews()).thenAnswer(
        (_) async => const ApiResult([]),
      );

      final result = await container.read(newsProvider.future);
      expect(result.data, isNotEmpty);
      expect(result.data.first.title, 'Official Apex Legends News');
    });

    test('deduplicates pinned articles from API results', () async {
      final apiArticles = [
        const NewsArticle(
          title: 'Official Apex Legends News',
          description: 'Duplicate of pinned',
          link: 'https://www.ea.com/games/apex',
          imageUrl: '',
        ),
        const NewsArticle(
          title: 'New Season',
          description: 'Fresh content',
          link: 'https://example.com/season',
          imageUrl: '',
        ),
      ];

      when(() => mockNewsService.getNews()).thenAnswer(
        (_) async => ApiResult(apiArticles),
      );

      final result = await container.read(newsProvider.future);
      expect(
        result.data.where((a) => a.link == 'https://www.ea.com/games/apex'),
        hasLength(1),
      );
    });

    test('returns pinned news on API failure', () async {
      when(() => mockNewsService.getNews()).thenThrow(Exception('Network error'));

      final result = await container.read(newsProvider.future);
      expect(result.data, isNotEmpty);
      expect(result.data.first.title, 'Official Apex Legends News');
    });

    test('preserves API staleness metadata', () async {
      final staleAt = DateTime.now().add(const Duration(hours: 1));
      when(() => mockNewsService.getNews()).thenAnswer(
        (_) async => ApiResult(
          [
            const NewsArticle(
              title: 'Test',
              description: 'Test',
              link: 'https://example.com',
              imageUrl: '',
            ),
          ],
          staleAt: staleAt,
        ),
      );

      final result = await container.read(newsProvider.future);
      expect(result.staleAt, staleAt);
    });
  });
}
