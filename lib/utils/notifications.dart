import 'package:flutter/material.dart';
import 'theme.dart';

extension ScaffoldMessengerX on ScaffoldMessengerState {
  void showMessage(
    String text, {
    Duration duration = const Duration(seconds: 4),
  }) {
    showSnackBar(SnackBar(content: Text(text), duration: duration));
  }

  void showError(String text) {
    showSnackBar(SnackBar(content: Text(text), backgroundColor: AppTheme.red));
  }
}

extension BuildContextMessengerX on BuildContext {
  void showMessage(
    String text, {
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(this).showMessage(text, duration: duration);
  }

  void showError(String text) {
    ScaffoldMessenger.of(this).showError(text);
  }
}
