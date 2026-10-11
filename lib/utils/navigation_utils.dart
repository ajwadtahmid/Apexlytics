import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_logger.dart';
import 'notifications.dart';

extension NavigationX on BuildContext {
  void pushPage(Widget page) {
    Navigator.of(this).push(MaterialPageRoute(builder: (_) => page));
  }
}

/// Opens [uri] outside the app, and says so when that did not work. A launch
/// fails by returning false or by throwing (Android throws when no app handles
/// the link, e.g. `mailto:` with no mail app); both show "Could not open link".
Future<void> openExternalLink(BuildContext context, Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    // Type only: the message can quote the link.
    log.w('Could not open a link (${e.runtimeType})');
  }
  if (!opened && context.mounted) context.showMessage('Could not open link');
}
