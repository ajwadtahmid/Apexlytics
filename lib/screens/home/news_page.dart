import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/api_constants.dart';
import '../../models/news_article.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart' show SectionLabel;

class NewsPage extends StatelessWidget {
  final List<NewsArticle> articles;
  const NewsPage({super.key, required this.articles});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('News & ALGS')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          const SectionLabel(label: 'News', icon: Icons.newspaper_outlined),
          if (articles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.lg),
              child: Center(
                child: Text(
                  'No news right now.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            )
          else
            for (final article in articles) ...[
              _ArticleCard(article: article),
              const SizedBox(height: AppTheme.sm),
            ],
          const SizedBox(height: AppTheme.md),
          const SectionLabel(label: 'ALGS', icon: Icons.emoji_events),
          const _LinkCard(
            title: 'Official ALGS Website',
            description:
                'Official website for the Apex Legends Global Series (ALGS)',
            url: ApiConstants.algsWebsiteUrl,
          ),
          const SizedBox(height: AppTheme.sm),
          const _LinkCard(
            title: 'ALGS Statistics',
            description:
                'ALGS player and team statistics from Apex Legends Status.',
            url: ApiConstants.algsStatsUrl,
          ),
          const SizedBox(height: AppTheme.sm),
          const _LinkCard(
            title: 'Unofficial Competitive Apex Subreddit',
            description: 'Community discussion for competitive Apex Legends.',
            url: ApiConstants.competitiveSubredditUrl,
          ),
        ],
      ),
    );
  }
}

/// Shared card shell for both a news article ([_ArticleCard]) and a static
/// resource link ([_LinkCard]): an optional image, then a row pairing the
/// title/description block against a trailing open-in-new icon on the right
/// — the icon appears whenever [url] is non-empty and marks the whole card as
/// an outgoing link. Tapping anywhere opens [url] externally.
class _CardTile extends StatelessWidget {
  final String title;
  final String description;
  final String imageUrl;
  final String url;

  const _CardTile({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: url.isEmpty
            ? null
            : () async {
                final uri = Uri.tryParse(url);
                if (uri == null) return;
                final ok = await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                );
                if (!ok && context.mounted) {
                  context.showMessage('Could not open link');
                }
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusMd),
                ),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: AppTheme.newsImageHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (ctx, url) => Container(
                    height: AppTheme.newsImageHeight,
                    color: AppTheme.surface2,
                  ),
                  errorWidget: (ctx, url, err) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (url.isNotEmpty) ...[
                    const SizedBox(width: AppTheme.sm),
                    const Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One news article: image (if any), title, description, and a trailing
/// open-in-new icon that opens the source link externally.
class _ArticleCard extends StatelessWidget {
  final NewsArticle article;
  const _ArticleCard({required this.article});

  @override
  Widget build(BuildContext context) => _CardTile(
    title: article.title,
    description: article.description,
    imageUrl: article.imageUrl,
    url: article.link,
  );
}

/// One static resource link (e.g. the ALGS site): same shell as
/// [_ArticleCard], minus the image (none is given for these).
class _LinkCard extends StatelessWidget {
  final String title;
  final String description;
  final String url;

  const _LinkCard({
    required this.title,
    required this.description,
    required this.url,
  });

  @override
  Widget build(BuildContext context) => _CardTile(
    title: title,
    description: description,
    imageUrl: '',
    url: url,
  );
}
