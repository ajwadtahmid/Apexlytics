import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../providers/settings_provider.dart';
import '../utils/theme.dart';
import 'player_lookup_form.dart';

class ProfileManagerSheet extends ConsumerStatefulWidget {
  const ProfileManagerSheet({super.key});

  @override
  ConsumerState<ProfileManagerSheet> createState() => _ProfileManagerSheetState();
}

class _ProfileManagerSheetState extends ConsumerState<ProfileManagerSheet> {
  bool _isAdding = false;
  int? _editingIndex; // null = list view; non-null = slot index being edited

  Future<void> _switchTo(int index) async {
    await ref.read(playerSettingsProvider.notifier).setActiveProfileIndex(index);
    if (mounted) Navigator.pop(context);
  }

  void _startEdit(int index) => setState(() {
    _isAdding = false;
    _editingIndex = index;
  });

  void _startAdd() => setState(() {
    _isAdding = true;
    _editingIndex = null;
  });

  void _cancelEdit() => setState(() {
    _isAdding = false;
    _editingIndex = null;
  });

  Future<void> _removeProfile(int index) async {
    await ref.read(playerSettingsProvider.notifier).removeProfile(index);
    // If the form was open for this specific slot, return to the list.
    if (_editingIndex == index && mounted) {
      setState(() { _isAdding = false; _editingIndex = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(playerSettingsProvider.select((s) => s.profiles));
    final activeProfileIndex =
        ref.watch(playerSettingsProvider.select((s) => s.activeProfileIndex));
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(AppTheme.md, AppTheme.md, AppTheme.md, AppTheme.md + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.md),
          if (_editingIndex != null || _isAdding) ...[
            _buildLookupView(profiles),
          ] else ...[
            _buildProfileList(profiles, activeProfileIndex),
          ],
          const SizedBox(height: AppTheme.sm),
        ],
      ),
    );
  }

  Widget _buildProfileList(List<PlayerProfile> profiles, int activeProfileIndex) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'My Profiles',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppTheme.md),
        for (int i = 0; i < profiles.length; i++) ...[
          _ProfileTile(
            profile: profiles[i],
            isActive: i == activeProfileIndex,
            onSwitch: () => _switchTo(i),
            onEdit: () => _startEdit(i),
            onRemove: () => _removeProfile(i),
          ),
          const SizedBox(height: AppTheme.sm),
        ],
        if (profiles.length < PlayerSettingsNotifier.maxProfileCount)
          InkWell(
            onTap: _startAdd,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.md),
              decoration: BoxDecoration(
                color: AppTheme.surface2,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: AppTheme.muted.withAlpha(60), width: 1),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, color: AppTheme.accent, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Add Profile',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLookupView(List<PlayerProfile> profiles) {
    final isAdding = _isAdding;
    final notifier = ref.read(playerSettingsProvider.notifier);
    final editedProfile =
        !isAdding && _editingIndex != null && _editingIndex! < profiles.length
            ? profiles[_editingIndex!]
            : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: _cancelEdit,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              child: const Padding(
                padding: EdgeInsets.all(AppTheme.xs),
                child: Icon(Icons.arrow_back, size: 20),
              ),
            ),
            const SizedBox(width: AppTheme.sm),
            Text(
              isAdding ? 'Add Profile' : 'Edit Profile',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.md),
        PlayerLookupForm(
          submitLabel: isAdding ? 'Add Profile' : 'Update Profile',
          initialName: editedProfile?.name,
          initialPlatform: editedProfile?.platform,
          onPlayerFound: isAdding
              ? (name, uid, platform) => notifier.addProfile(name, uid, platform)
              : (name, uid, platform) =>
                  notifier.updateProfile(_editingIndex!, name, uid, platform),
          onSuccess: () {
            if (mounted) setState(() => _editingIndex = null);
          },
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final PlayerProfile profile;
  final bool isActive;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.onSwitch,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isActive ? null : onSwitch,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.md,
          vertical: AppTheme.sm,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accent.withAlpha(20) : AppTheme.surface2,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: isActive
              ? Border.all(color: AppTheme.accent, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.person,
              color: isActive ? AppTheme.accent : AppTheme.muted,
              size: 20,
            ),
            const SizedBox(width: AppTheme.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: TextStyle(
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    ApiConstants.labelFor(profile.platform),
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check_circle,
                  color: AppTheme.accent,
                  size: 16,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              color: AppTheme.muted,
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: AppTheme.sm),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              color: AppTheme.red,
              onPressed: onRemove,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
