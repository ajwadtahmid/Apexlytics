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
