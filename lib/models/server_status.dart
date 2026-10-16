class ServerStatus {
  final Map<String, ServiceStatus> services;

  ServerStatus({required this.services});

  factory ServerStatus.fromJson(Map<String, dynamic> json) {
    final services = <String, ServiceStatus>{};
    json.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final regions = <String, RegionStatus>{};
        value.forEach((regionKey, regionValue) {
          if (regionValue is Map<String, dynamic> &&
              regionValue.containsKey('Status')) {
            regions[regionKey] = RegionStatus.fromJson(regionValue);
          }
        });
        if (regions.isNotEmpty) {
          services[key] = ServiceStatus(name: key, regions: regions);
        }
      }
    });
    return ServerStatus(services: services);
  }
}

class ServiceStatus {
  final String name;
  final Map<String, RegionStatus> regions;

  ServiceStatus({required this.name, required this.regions});

  String get overallStatus {
    final statuses = regions.values.map((r) => r.status).toList();
    if (statuses.any((s) => s == 'DOWN')) return 'DOWN';
    if (statuses.any((s) => s == 'SLOW')) return 'SLOW';
    // Anything else that isn't up is shown as it came, not as healthy.
    return statuses.firstWhere(
      (s) => s != 'UP' && s != 'OK',
      orElse: () => 'UP',
    );
  }

  static const priorityKeys = {
    'Origin_login',
    'EA_novafusion',
    'EA_accounts',
    'ApexOauth_Crossplay',
  };

  static const _labels = {
    'ApexOauth_Crossplay': 'Apex Crossplay',
    'EA_accounts': 'EA Accounts',
    'EA_novafusion': 'EA Nova Fusion',
    'Origin_login': 'Origin Login',
    'selfCoreTest': 'Apex Status API',
    'otherPlatforms': 'Other Platforms',
  };

  String get displayName => _labels[name] ?? name;
}

class RegionStatus {
  final String status;
  final int responseTime;

  RegionStatus({
    required this.status,
    required this.responseTime,
  });

  factory RegionStatus.fromJson(Map<String, dynamic> json) {
    return RegionStatus(
      status: json['Status'] as String? ?? 'UNKNOWN',
      responseTime: (json['ResponseTime'] as num?)?.toInt() ?? 0,
    );
  }
}
