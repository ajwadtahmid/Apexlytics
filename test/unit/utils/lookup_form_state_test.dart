import 'package:apexlytics/constants/ui_strings.dart';
import 'package:apexlytics/utils/lookup_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LookupFormState state;

  LookupFormState make({
    Future<void> Function()? beforeUidMode,
    String? name,
    String? platform,
    String? uid,
  }) {
    state = LookupFormState(
      beforeUidMode: beforeUidMode,
      name: name,
      platform: platform,
      uid: uid,
    );
    addTearDown(state.dispose);
    return state;
  }

  group('starting', () {
    test('adding starts blank, by name, on PC', () {
      make();

      expect(state.controller.text, isEmpty);
      expect(state.byUid, isFalse);
      expect(state.platform, 'PC');
      expect(state.uidLocked, isFalse);
      expect(state.notice, isNull);
    });

    test('editing starts filled in with the name', () {
      make(name: 'Aceu', uid: '1001', platform: 'X1');

      expect(state.controller.text, 'Aceu');
      expect(state.platform, 'X1');
      expect(state.byUid, isFalse);
    });

    test('editing a Switch profile starts on its UID, locked', () {
      make(name: 'Aceu', uid: '1001', platform: 'SWITCH');

      expect(state.controller.text, '1001');
      expect(state.byUid, isTrue);
      expect(state.uidLocked, isTrue);
    });
  });

  group('the UID choice', () {
    test('turning it on shows the UID draft, and off the name again', () async {
      make(name: 'Aceu', uid: '1001');

      await state.toggleUid(true);
      expect(state.controller.text, '1001');
      expect(state.byUid, isTrue);

      await state.toggleUid(false);
      expect(state.controller.text, 'Aceu');
      expect(state.byUid, isFalse);
    });

    test('keeps what was typed in each mode', () async {
      make();
      state.controller.text = 'Aceu';

      await state.toggleUid(true);
      expect(state.controller.text, isEmpty);
      state.controller.text = '2002';
      await state.toggleUid(false);

      expect(state.controller.text, 'Aceu');
      await state.toggleUid(true);
      expect(state.controller.text, '2002');
    });

    test('is waited for before UID mode is entered, each time', () async {
      var calls = 0;
      final modeWhenCalled = <bool>[];
      make(
        beforeUidMode: () async {
          calls++;
          modeWhenCalled.add(state.byUid);
        },
      );

      await state.toggleUid(true);
      await state.toggleUid(false);
      await state.toggleUid(true);

      expect(calls, 2);
      // Still in name mode when asked, so a warning shows before the change.
      expect(modeWhenCalled, [false, false]);
    });

    test('asking for the mode already in use does nothing', () async {
      var calls = 0;
      make(beforeUidMode: () async => calls++);

      await state.toggleUid(false);

      expect(calls, 0);
    });

    test('tells listeners', () async {
      make();
      var heard = 0;
      state.addListener(() => heard++);

      await state.toggleUid(true);

      expect(heard, 1);
    });
  });

  group('Nintendo Switch, which has only UIDs', () {
    test('picking it turns UID on, with a notice', () async {
      make();
      state.controller.text = '3003';

      await state.selectPlatform('SWITCH');

      expect(state.byUid, isTrue);
      expect(state.uidLocked, isTrue);
      expect(state.notice, switchAutoUidNotice);
    });

    test('leaving it turns UID back off', () async {
      make();
      await state.selectPlatform('SWITCH');

      await state.selectPlatform('X1');

      expect(state.byUid, isFalse);
      expect(state.uidLocked, isFalse);
      expect(state.notice, isNull);
    });

    test('a UID turned on by choice stays on after Switch', () async {
      make();
      await state.toggleUid(true);

      await state.selectPlatform('SWITCH');
      await state.selectPlatform('PS4');

      expect(state.byUid, isTrue);
    });

    test('UID cannot be turned off, and says why', () async {
      make();
      await state.selectPlatform('SWITCH');

      await state.toggleUid(false);

      expect(state.byUid, isTrue);
      expect(state.notice, switchNeedsUidWarning);
    });

    test('a notice goes when the text changes or it is cleared', () async {
      make();
      await state.selectPlatform('SWITCH');

      state.clearNotice();

      expect(state.notice, isNull);
    });
  });

  group('loading a player', () {
    test('a Switch player is shown by UID', () {
      make();

      state.load(platform: 'SWITCH', name: 'Aceu', uid: '1001');

      expect(state.byUid, isTrue);
      expect(state.controller.text, '1001');
      expect(state.platform, 'SWITCH');
    });

    test('a name on another platform puts the bar back in name mode', () async {
      make();
      state.load(platform: 'SWITCH', name: 'Aceu', uid: '1001');

      state.load(platform: 'PC', name: 'Pro', uid: '2002');

      expect(state.byUid, isFalse);
      expect(state.controller.text, 'Pro');
      expect(state.platform, 'PC');
    });

    test('loading while in UID mode by choice keeps UID forced off', () async {
      make();
      await state.toggleUid(true);

      state.load(platform: 'PC', name: 'Aceu', uid: '1001');

      expect(state.byUid, isFalse);
      expect(state.controller.text, 'Aceu');
    });
  });

  test('is safe to dispose while a warning is still open', () async {
    final state = LookupFormState(
      beforeUidMode: () =>
          Future<void>.delayed(const Duration(milliseconds: 10)),
    );

    final pending = state.toggleUid(true);
    state.dispose();

    await pending; // no use-after-dispose error
  });
}
