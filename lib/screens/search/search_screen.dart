import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/search_provider.dart';
import '../../utils/lookup_form_state.dart';
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
  late final LookupFormState _lookup = LookupFormState(
    beforeUidMode: () => showUidWarningIfNeeded(context, ref),
  );

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  void _search() {
    final q = _lookup.controller.text.trim();
    if (q.isEmpty) return;
    if (_lookup.byUid && !isDigitsOnly(q)) {
      // Formatters should already guarantee this — belt and suspenders.
      _lookup.showNotice('UID must contain digits only.');
      return;
    }
    context.pushPage(
      PlayerResultPage(
        query: q,
        platform: _lookup.platform,
        searchByUid: _lookup.byUid,
      ),
    );
  }

  void _pickFavorite(PlayerRef fav) {
    final byUid = fav.hasUid;
    // Show the favourite as it would be searched: by name, or by UID on a
    // UID-only platform.
    _lookup.load(platform: fav.platform, name: fav.query, uid: fav.uid);
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.md,
              AppTheme.sm,
              AppTheme.md,
              0,
            ),
            child: LookupCard(
              state: _lookup,
              onSubmit: _search,
              arrowSubmits: true,
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(child: FavoritesPane(onPick: _pickFavorite)),
        ],
      ),
    );
  }
}
