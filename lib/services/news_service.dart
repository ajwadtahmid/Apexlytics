import '../models/news_article.dart';
import 'api_service.dart';
import '../constants/api_constants.dart';

class NewsService {
  final ApiService _api;
  NewsService(this._api);

  Future<ApiResult<List<NewsArticle>>> getNews({String lang = 'en-US'}) async {
    final result = await _api.getList(ApiConstants.newsPath, params: {'lang': lang});
    final articles = result.data
        .whereType<Map<String, dynamic>>()
        .map(NewsArticle.fromJson)
        .toList();
    return ApiResult(articles, staleAt: result.staleAt);
  }
}
