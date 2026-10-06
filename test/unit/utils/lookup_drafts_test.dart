import 'package:apexlytics/utils/lookup_drafts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LookupDrafts', () {
    test('starts empty in both modes', () {
      final drafts = LookupDrafts();
      expect(drafts.draftFor(uid: false), isEmpty);
      expect(drafts.draftFor(uid: true), isEmpty);
    });

    test('swapping keeps the text being left and returns the other draft', () {
      final drafts = LookupDrafts();

      // Typed a name, then switched to UID mode.
      expect(drafts.swapTo(uid: true, current: 'Aceu'), isEmpty);
      // Typed a UID, then switched back.
      expect(drafts.swapTo(uid: false, current: '12345'), 'Aceu');
      // And forth again.
      expect(drafts.swapTo(uid: true, current: 'Aceu2'), '12345');
      expect(drafts.draftFor(uid: false), 'Aceu2');
    });

    test('switching to UID carries an all-digits entry across and keeps it as '
        'the name draft', () {
      final drafts = LookupDrafts();

      expect(drafts.swapTo(uid: true, current: '1012345678'), '1012345678');
      expect(drafts.draftFor(uid: false), '1012345678');
    });

    test('a carried number is not remembered as a typed UID', () {
      final drafts = LookupDrafts();

      expect(drafts.swapTo(uid: true, current: '1012345678'), '1012345678');
      // Back to name mode, then a name with letters: nothing comes back.
      expect(drafts.swapTo(uid: false, current: '1012345678'), '1012345678');
      expect(drafts.swapTo(uid: true, current: 'Aceu1012345678'), isEmpty);
    });

    test('a UID actually typed in UID mode is still remembered', () {
      final drafts = LookupDrafts();

      expect(drafts.swapTo(uid: true, current: 'Aceu'), isEmpty);
      expect(drafts.swapTo(uid: false, current: '555'), 'Aceu');
      expect(drafts.swapTo(uid: true, current: 'Aceu2'), '555');
    });

    test('a name, or an existing UID draft, is never overwritten by the '
        'carry-over', () {
      final named = LookupDrafts();
      expect(named.swapTo(uid: true, current: 'Aceu'), isEmpty);

      final drafted = LookupDrafts()..stash(uid: true, text: '99');
      expect(drafted.swapTo(uid: true, current: '1012345678'), '99');
    });

    test('stash replaces one mode\'s draft without touching the other', () {
      final drafts = LookupDrafts()
        ..stash(uid: false, text: 'name')
        ..stash(uid: true, text: '99');

      drafts.stash(uid: false, text: 'other');

      expect(drafts.draftFor(uid: false), 'other');
      expect(drafts.draftFor(uid: true), '99');
    });
  });

  test('setFieldText puts the cursor at the end', () {
    final controller = TextEditingController(text: 'old');

    setFieldText(controller, 'Aceu');

    expect(controller.text, 'Aceu');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });
}
