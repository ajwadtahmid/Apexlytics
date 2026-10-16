import 'package:apexlytics/models/server_status.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceStatus service(List<String> statuses) => ServiceStatus(
  name: 'EA_accounts',
  regions: {
    for (var i = 0; i < statuses.length; i++)
      'r$i': RegionStatus(status: statuses[i], responseTime: 10),
  },
);

void main() {
  test('down beats slow beats everything else', () {
    expect(service(['UP', 'SLOW', 'DOWN']).overallStatus, 'DOWN');
    expect(service(['UP', 'SLOW']).overallStatus, 'SLOW');
    expect(service(['UP', 'UP']).overallStatus, 'UP');
  });

  test('an unrecognised status is not reported as UP', () {
    expect(service(['UP', 'UNKNOWN']).overallStatus, 'UNKNOWN');
    expect(service(['MAINTENANCE']).overallStatus, 'MAINTENANCE');
  });
}
