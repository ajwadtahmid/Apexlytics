import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset path of the app's own license: the repo's `LICENSE`, bundled as is.
@visibleForTesting
const kAppLicenseAsset = 'LICENSE';

/// Adds Apexlytics' own license (GPL-3.0) to the list on the licenses page,
/// next to the packages Flutter collects on its own. Call once at startup.
void registerAppLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(kAppLicenseAsset);
    yield LicenseEntryWithLineBreaks(const ['Apexlytics'], text);
  });
}
