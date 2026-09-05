import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../auth/presentation/notifiers/auth_notifier.dart';
import '../../data/repositories/supabase_log_sheet_repository.dart';
import '../../domain/models/log_sheet_entry.dart';
import '../widgets/interactive_image_viewer.dart';

class LogSheetListScreen extends ConsumerStatefulWidget {
  const LogSheetListScreen({super.key});

  @override
  ConsumerState<LogSheetListScreen> createState() => _LogSheetListScreenState();
}

class _LogSheetListScreenState extends ConsumerState<LogSheetListScreen> {
  String _selectedSection = 'All';
  String _selectedWorkType = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final List<String> _sections = [
    'All',
    'Furnace / Induction',
    'CCM',
    'Rolling Mill',
    'Dedusting / Pollution',
    'Water Treatment',
    'Electrical Substation',
    'Utility / Compressor',
    'General Plant',
  ];

  final List<String> _workTypes = [
    'All',
    'Operation',
    'Inspection',
    'Breakdown Repair',
    'Cleaning / Routine',
    'Maintenance',
    'Electrical',
    'Mechanical',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    try {
      final repo = ref.read(supabaseLogSheetRepoProvider);
      final secList = await repo.getSectionSuggestions();
      final wtList = await repo.getWorkTypeSuggestions();
      if (mounted) {
        setState(() {
          for (final s in secList) {
            if (!_sections.contains(s)) _sections.add(s);
          }
          for (final wt in wtList) {
            if (!_workTypes.contains(wt)) _workTypes.add(wt);
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authNotifierProvider.notifier).currentUser;
    final isAdmin = user?.role == 'admin';

    final logsAsync = ref.watch(logSheetsListProvider((
      operatorId: isAdmin ? null : user?.id,
      section: _selectedSection == 'All' ? null : _selectedSection,
      workType: _selectedWorkType == 'All' ? null : _selectedWorkType,
    )));

    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'All Plant Log Sheets' : 'My Section Log Sheets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(logSheetsListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.logSheetAdd),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Log Entry'),
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Column(
              children: [
                // Search Input
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search equipment, description, operator...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),

                // Section & Work Type Filters
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedSection,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Section',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: _sections
                            .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedSection = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedWorkType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Work Type',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: _workTypes
                            .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedWorkType = val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Log List
          Expanded(
            child: logsAsync.when(
              loading: () => const LoadingWidget(message: 'Loading log sheets...'),
              error: (e, _) {
                final err = e.toString();
                final isTableMissing = err.contains('PGRST205') || err.contains('schema cache') || err.contains('not find the table');
                return EmptyStateWidget(
                  icon: Icons.table_chart_outlined,
                  title: isTableMissing ? 'Log Sheet Setup Required' : 'Unable to Load Logs',
                  subtitle: isTableMissing
                      ? 'The log_sheets table needs to be created in Supabase SQL editor once.\nCheck the SQL setup instructions.'
                      : 'Error: $e',
                  actionLabel: 'Try Again',
                  action: () => ref.invalidate(logSheetsListProvider),
                );
              },
              data: (logs) {
                var filtered = logs;
                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((l) =>
                      l.equipmentType.toLowerCase().contains(_searchQuery) ||
                      l.description.toLowerCase().contains(_searchQuery) ||
                      l.operatorName.toLowerCase().contains(_searchQuery) ||
                      l.section.toLowerCase().contains(_searchQuery) ||
                      l.workType.toLowerCase().contains(_searchQuery)).toList();
                }

                if (filtered.isEmpty) {
                  return EmptyStateWidget(
                    icon: Icons.article_outlined,
                    title: 'No Log Entries Found',
                    subtitle: 'Tap the button below to add your first log sheet entry.',
                    actionLabel: 'Add Log Entry',
                    action: () => context.push(RoutePaths.logSheetAdd),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length + 1, // extra padding for FAB
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      return const SizedBox(height: 72);
                    }
                    final entry = filtered[index];
                    return _LogSheetCard(
                      entry: entry,
                      canDelete: isAdmin || entry.operatorId == user?.id,
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Log Entry'),
                            content: const Text('Are you sure you want to delete this log sheet record?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(supabaseLogSheetRepoProvider).delete(entry.id);
                          ref.invalidate(logSheetsListProvider);
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogSheetCard extends StatelessWidget {
  const _LogSheetCard({
    required this.entry,
    required this.canDelete,
    required this.onDelete,
  });

  final LogSheetEntry entry;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logDate = DateTime.fromMillisecondsSinceEpoch(entry.logDate, isUtc: true).toLocal();
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(logDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Section & Work Type Chips + Delete
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.section,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.workType,
                    style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  dateStr,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
                if (canDelete) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Delete',
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Equipment Type
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.precision_manufacturing_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.equipmentType,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              entry.description,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 12),

            // Attached Photo with Pinch-to-Zoom Viewer
            if (entry.imageUrl != null && entry.imageUrl!.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  InteractiveImageViewer.show(
                    context,
                    imageUrl: entry.imageUrl!,
                    title: entry.equipmentType,
                    subtitle: '${entry.section} • $dateStr',
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          entry.imageUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported_rounded, color: Colors.grey),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.zoom_in_rounded, size: 16, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Tap for 2-Finger Zoom',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pinch with two fingers or double-tap to zoom up to 5x',
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Operator Footer
            Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'Logged by: ${entry.operatorName}',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
