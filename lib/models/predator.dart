class PredatorResponse {
  final Map<String, PlatformPredator> rp;

  PredatorResponse({required this.rp});

  factory PredatorResponse.fromJson(Map<String, dynamic> json) {
    final rpData = json['RP'] as Map<String, dynamic>? ?? {};
    final rp = <String, PlatformPredator>{};
    rpData.forEach((platform, data) {
      if (data is Map<String, dynamic>) {
        rp[platform] = PlatformPredator.fromJson(data);
      }
    });
    return PredatorResponse(rp: rp);
  }

  PlatformPredator? forPlatform(String platform) => rp[platform];
}

class PlatformPredator {
  final int minRp;
  final int totalMastersAndPreds;
  final DateTime? updatedAt;

  PlatformPredator({
    required this.minRp,
    required this.totalMastersAndPreds,
    this.updatedAt,
  });

  factory PlatformPredator.fromJson(Map<String, dynamic> json) {
    final ts = (json['updateTimestamp'] as num?)?.toInt() ?? 0;
    return PlatformPredator(
      minRp: (json['val'] as num?)?.toInt() ?? 0,
      totalMastersAndPreds:
          (json['totalMastersAndPreds'] as num?)?.toInt() ?? 0,
      updatedAt: ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts * 1000) : null,
    );
  }
}
