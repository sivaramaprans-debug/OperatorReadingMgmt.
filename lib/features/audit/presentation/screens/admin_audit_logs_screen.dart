import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../notifiers/audit_logs_notifier.dart';

class AdminAuditLogsScreen extends ConsumerWidget {
  const AdminAuditLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Audit Logs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go(RoutePaths.adminDashboard),
        ),
      ),
      body: logsAsync.when(
        loading: () => const LoadingWidget(message: 'Loading secure logs...'),
        error: (err, stack) => ErrorStateWidget(
          message: 'Failed to load audit logs',
          onRetry: () => ref.invalidate(auditLogsProvider),
        ),
        data: (logs) {
          if (logs.isEmpty) {
            return const EmptyStateWidget(
              icon: Icons.security_rounded,
              title: 'No Audit Logs',
              subtitle: 'The system has not recorded any events yet.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final log = logs[index];
              return _AuditLogTile(log: log);
            },
          );
        },
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  const _AuditLogTile({required this.log});
  final dynamic log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Determine icon based on entity type
    IconData icon = Icons.info_outline_rounded;
    Color iconColor = theme.colorScheme.onSurfaceVariant;
    if (log.entityType == 'reading') {
      icon = Icons.analytics_rounded;
      iconColor = AppColors.primary;
    } else if (log.entityType == 'operator') {
      icon = Icons.person_rounded;
      iconColor = AppColors.secondary;
    } else if (log.entityType == 'device') {
      icon = Icons.precision_manufacturing_rounded;
      iconColor = AppColors.tertiary;
    }

    final dateStr = DateFormat('MMM d, yyyy h:mm a').format(
      DateTime.fromMillisecondsSinceEpoch(log.createdAt, isUtc: true).toLocal(),
    );

    String metadataText = '';
    if (log.metadataJson != null && (log.metadataJson as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(log.metadataJson!);
        metadataText = const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        metadataText = log.metadataJson!;
      }
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withOpacity(0.1),
        foregroundColor: iconColor,
        child: Icon(icon),
      ),
      title: Text(
        '${log.action.toUpperCase()}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text('Actor: ${log.actorId} (${log.actorRole})'),
          Text('Target ID: ${log.entityId}'),
          if (metadataText.isNotEmpty)
            const Text('Details attached', style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
      trailing: Text(
        dateStr,
        style: theme.textTheme.bodySmall,
        textAlign: TextAlign.right,
      ),
      isThreeLine: true,
      onTap: () {
        if (metadataText.isNotEmpty) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Log Details'),
              content: SingleChildScrollView(
                child: Text(
                  metadataText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}
