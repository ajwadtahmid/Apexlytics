import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/api_constants.dart';
import '../../constants/ui_strings.dart';
import '../../providers/search_provider.dart';
import '../../utils/lookup_drafts.dart';
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
  final _drafts = LookupDrafts();
  String _platform = ApiConstants.defaultPlatform;
  bool _searchByUid = false;

  /// UID search is on only because Switch is selected; leaving Switch turns it off again.
  bool _uidForcedBySwitch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleUidSearch(bool value) async {
    if (value == _searchByUid) return;
    if (!value && ApiConstants.isUidOnly(_platform)) {
      // Switch is UID-only.
      _showSnack(switchNeedsUidWarning);
      return;
    }
    await _setSearchByUid(value);
  }

  /// Swaps the bar between its name and UID drafts.
  Future<void> _setSearchByUid(bool value) async {
    if (value && !_searchByUid) {
      await showUidWarningIfNeeded(context, ref);
    }
    if (!mounted) return;
    setState(() {
      setFieldText(
        _controller,
        _drafts.swapTo(uid: value, current: _controller.text),
      );
      _searchByUid = value;
    });
  }

  Future<void> _selectPlatform(String platform) async {
    setState(() => _platform = platform);
    if (ApiConstants.isUidOnly(platform)) {
      if (_searchByUid) return;
      _uidForcedBySwitch = true;
      await _setSearchByUid(true);
      if (mounted) _showSnack(switchAutoUidNotice);
    } else if (_uidForcedBySwitch) {
      // Leaving Switch: restore the toggle.
      _uidForcedBySwitch = false;
      await _setSearchByUid(false);
    }
  }

  void _search([String? query, String? platform]) {
    final q = (query ?? _controller.text).trim();
    if (q.isEmpty) return;
    if (_searchByUid && !isDigitsOnly(q)) {
      // Formatters should already guarantee this — belt and suspenders.
      _showSnack('UID must contain digits only.');
      return;
    }
    context.pushPage(
      PlayerResultPage(
        query: q,
        platform: platform ?? _platform,
        searchByUid: _searchByUid,
      ),
    );
  }

  void _pickFavorite(PlayerRef fav) {
    final byUid = fav.hasUid;
    // Show the favourite as it would be searched: by name, or by UID on a UID-only platform.
    final barByUid = ApiConstants.isUidOnly(fav.platform);
    setState(() {
      _platform = fav.platform;
      // Forced only if UID mode wasn't already on by choice.
      _uidForcedBySwitch =
          barByUid && (!_searchByUid || _uidForcedBySwitch);
      _drafts.stash(uid: _searchByUid, text: _controller.text);
      _searchByUid = barByUid;
      setFieldText(_controller, barByUid ? (fav.uid ?? '') : fav.query);
    });
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
            onPlatformChanged: _selectPlatform,
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
            keyboardType: searchByUid
                ? TextInputType.number
                : TextInputType.text,
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
          UidSuggestion(
            controller: controller,
            searchByUid: searchByUid,
            onUseUid: () => onSearchByUidChanged(true),
          ),
        ],
      ),
    );
  }
}
