import 'package:flutter/widgets.dart';

/// What the user last typed in a lookup field, per search mode. Switching between "by name"
/// and "by UID" shows the other mode's draft and keeps the text being left.
class LookupDrafts {
  String _name = '';
  String _uid = '';

  String draftFor({required bool uid}) => uid ? _uid : _name;

  void stash({required bool uid, required String text}) {
    if (uid) {
      _uid = text;
    } else {
      _name = text;
    }
  }

  /// Stashes [current] under the mode being left; returns the draft for the mode entered.
  String swapTo({required bool uid, required String current}) {
    stash(uid: !uid, text: current);
    return draftFor(uid: uid);
  }
}

/// Replaces [controller]'s text, cursor at the end (assigning `.text` leaves it invalid).
void setFieldText(TextEditingController controller, String text) {
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
}
