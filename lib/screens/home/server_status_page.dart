import 'package:flutter/material.dart';
import '../../constants/api_constants.dart';
import '../../models/server_status.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import '../../utils/navigation_utils.dart';

// ── Latency color helper ──────────────────────────────────────────────────────

Color latencyColor(int ms) {
  if (ms < 50) return AppTheme.green;
  if (ms < 200) return AppTheme.orange;
  return AppTheme.red;
}

class ServerStatusPage extends StatelessWidget {
  final ServerStatus status;
  const ServerStatusPage({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final services = status.services.values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Server Status')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppTheme.md),
              itemCount: services.length,
              itemBuilder: (context, i) {
                final svc = services[i];
                final color = AppTheme.statusColor(svc.overallStatus);
                return SurfaceCard(
                  margin: const EdgeInsets.only(bottom: AppTheme.sm),
                  padding: const EdgeInsets.all(AppTheme.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          StatusDot(color: color),
                          const SizedBox(width: AppTheme.sm),
                          Text(
                            svc.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              svc.overallStatus,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (svc.regions.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.sm),
                        Wrap(
                          spacing: AppTheme.sm,
                          runSpacing: 4,
                          children: svc.regions.entries.map((e) {
                            final rc = latencyColor(e.value.responseTime);
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatusDot(color: rc, size: 6),
                                const SizedBox(width: 4),
                                Text(
                                  '${e.key} | ${e.value.responseTime}ms',
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.md),
            child: GestureDetector(
              onTap: () =>
                  openExternalLink(context, Uri.parse(ApiConstants.apexStatusUrl)),
              child: const Text(
                'Data from apexlegendsstatus.com',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.blue,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
