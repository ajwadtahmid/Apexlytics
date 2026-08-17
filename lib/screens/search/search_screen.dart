import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/api_constants.dart';
import '../../providers/search_provider.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/theme.dart';
import '../../utils/uid_warning_dialog.dart';
import '../../widgets/widgets.dart';
import 'favorites_pane.dart';
import 'player_result_page.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _platform = ApiConstants.defaultPlatform;
  bool _searchByUid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleUidSearch(bool value) async {
    if (value && !_searchByUid) {
      await showUidWarningIfNeeded(context, ref);
    }
    if (!mounted) return;
    setState(() {
      _searchByUid = value;
      // inputFormatters only filter *future* edits — drop any non-digit text
      // already typed rather than let it be searched as a UID untouched.
      if (value && !isDigitsOnly(_controller.text)) _controller.clear();
    });
  }

  void _search([String? query, String? platform]) {
    final q = (query ?? _controller.text).trim();
    if (q.isEmpty) return;
    if (_searchByUid && !isDigitsOnly(q)) {
      // Formatters should already guarantee this — belt and suspenders.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('UID must contain digits only.')),
      );
      return;
    }
    context.pushPage(
      PlayerResultPage(query: q, platform: platform ?? _platform, searchByUid: _searchByUid),
    );
  }

  void _pickFavorite(PlayerRef fav) {
    final byUid = fav.hasUid;
    _controller.text = fav.query;
    setState(() => _platform = fav.platform);
    context.pushPage(
      PlayerResultPage(
        query: byUid ? fav.uid! : fav.query,
        platform: fav.platform,
        searchByUid: byUid,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          _SearchBar(
            controller: _controller,
            platform: _platform,
            searchByUid: _searchByUid,
            onPlatformChanged: (p) => setState(() => _platform = p),
            onSearchByUidChanged: _toggleUidSearch,
            onSearch: _search,
          ),
          Expanded(child: FavoritesPane(onPick: _pickFavorite)),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String platform;
  final bool searchByUid;
  final ValueChanged<String> onPlatformChanged;
  final ValueChanged<bool> onSearchByUidChanged;
  final VoidCallback onSearch;

  const _SearchBar({
    required this.controller,
    required this.platform,
    required this.searchByUid,
    required this.onPlatformChanged,
    required this.onSearchByUidChanged,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.md,
        AppTheme.sm,
        AppTheme.md,
        AppTheme.md,
      ),
      color: AppTheme.surface,
      child: Column(
        children: [
          TextField(
            controller: controller,
            onSubmitted: (_) => onSearch(),
            textInputAction: TextInputAction.search,
            keyboardType: searchByUid ? TextInputType.number : TextInputType.text,
            inputFormatters: searchByUid ? uidOnlyInputFormatters : null,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Name or UID…',
              prefixIcon: const Icon(Icons.search, color: AppTheme.muted),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, color: AppTheme.accent),
                onPressed: onSearch,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.sm),
          PlatformPicker(selected: platform, onChanged: onPlatformChanged),
          const SizedBox(height: AppTheme.sm),
          UidSearchToggle(value: searchByUid, onChanged: onSearchByUidChanged),
        ],
      ),
    );
  }
}
