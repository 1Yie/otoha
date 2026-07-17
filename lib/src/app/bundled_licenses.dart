import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _bundledLicensesRegistered = false;

void registerBundledLicenses() {
  if (_bundledLicensesRegistered) return;
  _bundledLicensesRegistered = true;

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(
      'assets/font/MiSans_LICENSE.txt',
    );
    yield LicenseEntryWithLineBreaks(const <String>['MiSans'], license);
  });
}
