import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../models/news_article.dart';
import '../services/api_service.dart';
import '../utils/app_logger.dart';
import 'api_provider.dart';

const _pinnedNews = [
  NewsArticle(
    title: 'Official Apex Legends News',
    description: 'Patch notes, season updates, and announcements from EA.',
    link: ApiConstants.eaNewsUrl,
    imageUrl: '',
  ),
];

class NewsNotifier extends AsyncNotifier<ApiResult<List<NewsArticle>>> {
  @override
  Future<ApiResult<List<NewsArticle>>> build() async {
    try {
      final result = await ref.watch(newsServiceProvider).getNews();
      // Deduplicate pinned articles: exclude any API result with a link already in pinned.
      final pinnedLinks = {for (final article in _pinnedNews) article.link};
      final apiArticles = result.data
          .where((article) => !pinnedLinks.contains(article.link))
          .toList();
      return ApiResult([
        ..._pinnedNews,
        ...apiArticles,
      ], staleAt: result.staleAt);
    } catch (e, st) {
      log.w('news fetch failed', error: e, stackTrace: st);
      // If news API fails, return just the pinned news
      return const ApiResult(_pinnedNews);
    }
  }
}

final newsProvider =
    AsyncNotifierProvider<NewsNotifier, ApiResult<List<NewsArticle>>>(
      NewsNotifier.new,
    );
