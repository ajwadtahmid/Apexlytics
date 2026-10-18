import 'package:flutter/widgets.dart';
import '../constants/api_constants.dart';
import '../constants/ui_strings.dart';
import 'lookup_drafts.dart';

/// What a player lookup form is showing: the typed text, the platform, and
/// whether the text is a name or a UID. One of these backs every lookup (Search,
/// first-time setup, Add / Edit Profile), so they all treat the UID choice and
/// Nintendo Switch, which can only be searched by UID, the same way.
class LookupFormState extends ChangeNotifier {
  /// Called, and waited for, each time UID mode is about to be entered, so a
  /// warning can be shown first (the caller decides whether it already has been).
  final Future<void> Function()? beforeUidMode;

  /// An edit starts filled in: [name], [uid] and [platform] of the profile.
  /// Adding (no [name]) starts blank.
  LookupFormState({
    this.beforeUidMode,
    String? name,
    String? platform,
    String? uid,
  }) {
    if (name != null) {
      this.platform = platform ?? ApiConstants.defaultPlatform;
      _drafts.stash(uid: false, text: name);
      _drafts.stash(uid: true, text: uid ?? '');
    }
    // Opened on Switch (editing one): UID search is forced, so leaving Switch
    // returns to name.
    byUid = _forcedBySwitch = ApiConstants.isUidOnly(this.platform);
    setFieldText(controller, _drafts.draftFor(uid: byUid));
  }

  final TextEditingController controller = TextEditingController();
  final LookupDrafts _drafts = LookupDrafts();

  String platform = ApiConstants.defaultPlatform;
  bool byUid = false;

  /// A heads-up for the player (mode switched for them, a refused change, a
  /// throttled tap); not an error.
  String? notice;

  /// UID search is on only because Switch is selected; leaving Switch turns it
  /// off again. If it was already on by choice, it stays on.
  bool _forcedBySwitch = false;
  bool _disposed = false;

  /// Whether the UID choice can't be changed: Switch has no lookup by name.
  bool get uidLocked => ApiConstants.isUidOnly(platform);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    _changed();
  }

  void showNotice(String text) {
    notice = text;
    _changed();
  }

  /// Turns UID search on or off. Refused, with a notice, off on Switch.
  Future<void> toggleUid(bool value) async {
    if (value == byUid) return;
    if (!value && uidLocked) {
      showNotice(switchNeedsUidWarning);
      return;
    }
    await _setUid(value);
  }

  /// Swaps the field between its name and UID drafts.
  Future<void> _setUid(bool value) async {
    if (value && !byUid) await beforeUidMode?.call();
    if (_disposed) return;
    setFieldText(
      controller,
      _drafts.swapTo(uid: value, current: controller.text),
    );
    byUid = value;
    notice = null;
    _changed();
  }

  Future<void> selectPlatform(String next) async {
    platform = next;
    notice = null;
    _changed();
    if (ApiConstants.isUidOnly(next)) {
      if (byUid) return;
      _forcedBySwitch = true;
      await _setUid(true);
      if (!_disposed) showNotice(switchAutoUidNotice);
    } else if (_forcedBySwitch) {
      // Leaving Switch: restore the choice.
      _forcedBySwitch = false;
      await _setUid(false);
    }
  }

  /// Shows a player as they would be searched: by name, or by UID on a
  /// UID-only platform. What was typed in the mode being left is kept.
  void load({required String platform, required String name, String? uid}) {
    final barByUid = ApiConstants.isUidOnly(platform);
    // Forced only if UID mode wasn't already on by choice.
    _forcedBySwitch = barByUid && (!byUid || _forcedBySwitch);
    _drafts.stash(uid: byUid, text: controller.text);
    this.platform = platform;
    byUid = barByUid;
    setFieldText(controller, barByUid ? (uid ?? '') : name);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    controller.dispose();
    super.dispose();
  }
}
