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

  /// A number carried over from the name field, so leaving UID mode with it untouched does
  /// not save it as a UID the user typed (it would come back later next to a different name).
  String? _carried;

  /// Stashes [current] under the mode being left; returns the draft for the mode entered.
  ///
  /// Switching to UID with nothing drafted there carries an all-digits [current] across
  /// (a UID pasted before ticking the box), and still keeps it as the name draft. Anything
  /// with a letter in it is never carried.
  String swapTo({required bool uid, required String current}) {
    if (!uid && current == _carried && _uid.isEmpty) {
      _carried = null;
      return draftFor(uid: false);
    }
    stash(uid: !uid, text: current);
    _carried = null;
    if (uid && _uid.isEmpty && RegExp(r'^\d+$').hasMatch(current)) {
      _carried = current;
      return current;
    }
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
