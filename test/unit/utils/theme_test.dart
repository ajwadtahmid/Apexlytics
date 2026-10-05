import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/theme.dart';

void main() {
  test('signColor is green for a gain and red for a loss', () {
    expect(AppTheme.signColor(true), AppTheme.green);
    expect(AppTheme.signColor(false), AppTheme.red);
  });
}
