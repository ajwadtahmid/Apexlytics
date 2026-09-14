import 'package:flutter/material.dart';

extension NavigationX on BuildContext {
  void pushPage(Widget page) {
    Navigator.of(this).push(MaterialPageRoute(builder: (_) => page));
  }
}
