import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../notifiers/admin_readings_notifier.dart';
import '../../domain/usecases/export_readings_usecase.dart';
import '../widgets/admin_summary_table.dart';
import '../widgets/readings_calculated_table.dart';

class AdminReadingsListScreen extends ConsumerStatefulWidget {
  const AdminReadingsListScreen({super.key});

  @override
  ConsumerState<AdminReadingsListScreen> createState() =>
      _AdminReadingsListScreenState();
}

class _AdminReadingsListScreenState
    extends ConsumerState<AdminReadingsListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Readings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go(RoutePaths.adminDashboard),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded),
            tooltip: 'Check for Updates',
            onPressed: () async {
              final url = Uri.parse('https://github.com/sivaramaprans-debug/OperatorReadingMgmt./releases/latest');
              try {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not launch update page.')),
                  );
                }
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Export Readings',
            onSelected: (value) async {
              final readingsAsync = ref.read(adminReadingsProvider);
              if (readingsAsync.value == null || readingsAsync.value!.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No data available to export.')),
                  );
                }
                return;
              }
              
              final usecase = ExportReadingsUseCase();
              bool success = false;
              if (value == 'excel') {
                success = await usecase.exportToExcel(readingsAsync.value!);
              } else if (value == 'pdf') {
                success = await usecase.exportToPdf(readingsAsync.value!);
              }
              
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export saved successfully.')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export was cancelled or failed.')),
                  );
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Export to Excel'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Export to PDF'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Detail'),
            Tab(text: 'Admin Sheet'),
            Tab(text: 'Heat Summary'),
          ],
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _DetailTab(),
          _SummaryTab(readingType: 'day'),
          _SummaryTab(readingType: 'heat'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(RoutePaths.adminReadingAdd),
        icon: const Icon(Icons.add_chart_rounded),
        label: const Text('Add Reading'),
      ),
    );
  }
}

// ── Tab 1: Detail ─────────────────────────────────────────────────────────────

class _DetailTab extends ConsumerWidget {
  const _DetailTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingsAsync = ref.watch(adminReadingsProvider);

    return Column(
      children: [
        const _FilterBar(),
        Expanded(
          child: SelectionArea(
            child: readingsAsync.when(
            loading: () => const LoadingWidget(message: 'Searching readings...'),
            error: (err, stack) => ErrorStateWidget(
              message: 'Failed to search readings',
              onRetry: () => ref.invalidate(adminReadingsProvider),
            ),
            data: (readings) {
              if (readings.isEmpty) {
                return const EmptyStateWidget(
                  icon: Icons.search_off_rounded,
                  title: 'No Readings Found',
                  subtitle: 'Try adjusting your filters.',
                );
              }

              // Group readings by device name
              final Map<String, List<SupabaseReadingWithDetails>> grouped = {};
              for (final r in readings) {
                grouped.putIfAbsent(r.deviceName, () => []).add(r);
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: grouped.entries.map((entry) {
                  final deviceReadings = entry.value;
                  final firstReading = deviceReadings.first;
                  final matrixUnits = firstReading.deviceMatrix.isEmpty
                      ? <String>[]
                      : firstReading.deviceMatrix
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();
                  final dayMatrixUnits = firstReading.deviceDayMatrix.isEmpty
                      ? <String>[]
                      : firstReading.deviceDayMatrix
                          .split(',')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList();
                  final allUnits = {...matrixUnits, ...dayMatrixUnits}.toList();

                  final heatFactors = parseFactorMap(firstReading.deviceHeatUnitFactors);
                  final dayFactors = parseFactorMap(firstReading.deviceDayUnitFactors);
                  final opNames = {
                    for (final rwd in deviceReadings) rwd.reading.id: rwd.operatorName
                  };

                  return _AdminDeviceReadingsSection(
                    deviceName: entry.key,
                    deviceId: firstReading.reading.deviceId,
                    readings: deviceReadings,
                    matrixUnits: allUnits,
                    showTypeColumn: firstReading.deviceRequiresHeatDay,
                    heatUnitFactors: heatFactors,
                    dayUnitFactors: dayFactors,
                    operatorNames: opNames,
                  );
                }).toList(),
              );
            },
          ),
        ),
      ),
      ],
    );
  }
}

// ── Tab 2 & 3: Summary ────────────────────────────────────────────────────────

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.readingType});
  final String readingType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _FilterBar(readingType: readingType),
        Expanded(
          child: SelectionArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AdminSummaryTable(readingType: readingType),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Filter Bar ────────────────────────────────────────────────────────────────

class _FilterBar extends ConsumerWidget {
  const _FilterBar({this.readingType});
  final String? readingType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(adminReadingsFilterProvider);
    final theme = Theme.of(context);
    final operatorsAsync = ref.watch(allOperatorsProvider);
    final devicesAsync = ref.watch(allDevicesProvider);

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter controls row: Operator, Type, Date Range, Clear All
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Operator filter dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: filter.operatorId,
                      hint: const Text('All Operators', style: TextStyle(fontSize: 13)),
                      isDense: true,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Operators', style: TextStyle(fontSize: 13))),
                        if (operatorsAsync.value != null)
                          ...operatorsAsync.value!.map((o) => DropdownMenuItem(
                                value: o.id,
                                child: Text(o.username, style: const TextStyle(fontSize: 13)),
                              )),
                      ],
                      onChanged: (val) {
                        ref.read(adminReadingsFilterProvider.notifier).state = AdminReadingsFilter(
                          operatorId: val,
                          deviceIds: filter.deviceIds,
                          readingType: filter.readingType,
                          fromDateMs: filter.fromDateMs,
                          toDateMs: filter.toDateMs,
                        );
                      },
                    ),
                  ),
                ),

                // Reading type dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: filter.readingType,
                      hint: const Text('All Types', style: TextStyle(fontSize: 13)),
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('All Types', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'heat', child: Text('Heat', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'day', child: Text('Day', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'standard', child: Text('Standard', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (val) {
                        ref.read(adminReadingsFilterProvider.notifier).state = AdminReadingsFilter(
                          operatorId: filter.operatorId,
                          deviceIds: filter.deviceIds,
                          readingType: val,
                          fromDateMs: filter.fromDateMs,
                          toDateMs: filter.toDateMs,
                        );
                      },
                    ),
                  ),
                ),

                // Prominent Date Range filter button
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    backgroundColor: (filter.fromDateMs != null && filter.toDateMs != null)
                        ? theme.colorScheme.primaryContainer
                        : null,
                  ),
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(
                    (filter.fromDateMs != null && filter.toDateMs != null)
                        ? '${DateFormat('dd MMM yy').format(DateTime.fromMillisecondsSinceEpoch(filter.fromDateMs!, isUtc: true))} - ${DateFormat('dd MMM yy').format(DateTime.fromMillisecondsSinceEpoch(filter.toDateMs!, isUtc: true))}'
                        : 'Filter Date Range',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDateRange: (filter.fromDateMs != null && filter.toDateMs != null)
                          ? DateTimeRange(
                              start: DateTime.fromMillisecondsSinceEpoch(filter.fromDateMs!, isUtc: true).toLocal(),
                              end: DateTime.fromMillisecondsSinceEpoch(filter.toDateMs!, isUtc: true).toLocal(),
                            )
                          : null,
                    );
                    if (picked != null) {
                      final startMs = DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0)
                          .toUtc()
                          .millisecondsSinceEpoch;
                      final endMs = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59)
                          .toUtc()
                          .millisecondsSinceEpoch;
                      ref.read(adminReadingsFilterProvider.notifier).state = AdminReadingsFilter(
                        operatorId: filter.operatorId,
                        deviceIds: filter.deviceIds,
                        readingType: filter.readingType,
                        fromDateMs: startMs,
                        toDateMs: endMs,
                      );
                    }
                  },
                ),

                if (filter.fromDateMs != null || filter.toDateMs != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Clear Date Filter',
                    onPressed: () {
                      ref.read(adminReadingsFilterProvider.notifier).state = AdminReadingsFilter(
                        operatorId: filter.operatorId,
                        deviceIds: filter.deviceIds,
                        readingType: filter.readingType,
                        fromDateMs: null,
                        toDateMs: null,
                      );
                    },
                  ),

                TextButton.icon(
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear All'),
                  onPressed: () {
                    ref.read(adminReadingsFilterProvider.notifier).state = const AdminReadingsFilter();
                  },
                ),
              ],
            ),
          ),

          // Device multi-select chips
          Builder(builder: (context) {
            var devices = devicesAsync.value ?? <SupabaseDevice>[];
            if (readingType == 'heat') {
              devices = devices.where((d) => d.requiresHeatDay).toList();
            }
            if (devices.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Filter by Device', style: theme.textTheme.labelLarge),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    children: devices.map((device) {
                      final isSelected = filter.deviceIds.contains(device.id);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(device.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            final newIds = List<String>.from(filter.deviceIds);
                            if (selected) {
                              newIds.add(device.id);
                            } else {
                              newIds.remove(device.id);
                            }
                            ref.read(adminReadingsFilterProvider.notifier).state =
                                AdminReadingsFilter(
                              operatorId: filter.operatorId,
                              deviceIds: newIds,
                              readingType: filter.readingType,
                              fromDateMs: filter.fromDateMs,
                              toDateMs: filter.toDateMs,
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          }),

          const Divider(height: 1),
        ],
      ),
    );
  }
}

// ── Per-Device Section (Detail Tab) ──────────────────────────────────────────

/// Stateful so it can hold its own local type filter.
class _AdminDeviceReadingsSection extends ConsumerStatefulWidget {
  const _AdminDeviceReadingsSection({
    required this.deviceName,
    required this.deviceId,
    required this.readings,
    required this.matrixUnits,
    required this.showTypeColumn,
    required this.heatUnitFactors,
    required this.dayUnitFactors,
    required this.operatorNames,
  });
  final String deviceName;
  final String deviceId;
  final List<SupabaseReadingWithDetails> readings;
  final List<String> matrixUnits;
  final bool showTypeColumn;
  final Map<String, double> heatUnitFactors;
  final Map<String, double> dayUnitFactors;
  final Map<String, String> operatorNames;

  @override
  ConsumerState<_AdminDeviceReadingsSection> createState() =>
      _AdminDeviceReadingsSectionState();
}

class _AdminDeviceReadingsSectionState
    extends ConsumerState<_AdminDeviceReadingsSection> {
  String? _selectedType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Apply local per-device type filter
    final filtered = _selectedType == null
        ? widget.readings
        : widget.readings
            .where((rwd) => rwd.reading.readingType == _selectedType)
            .toList();

    final plainReadings = filtered.map((rwd) => rwd.reading).toList();
    final opNamesFiltered = {
      for (final rwd in filtered) rwd.reading.id: rwd.operatorName
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device header with per-device type filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.electric_meter_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.deviceName,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                // Reading count badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.readings.length} reading${widget.readings.length == 1 ? '' : 's'}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const SizedBox(width: 8),
                // Per-device type filter (same as operator panel)
                if (widget.showTypeColumn)
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _selectedType,
                        hint: const Text('All Types',
                            style: TextStyle(fontSize: 12)),
                        icon: const Icon(Icons.arrow_drop_down, size: 16),
                        items: const [
                          DropdownMenuItem(
                              value: null,
                              child: Text('All Types',
                                  style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(
                              value: 'heat',
                              child:
                                  Text('Heat', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(
                              value: 'day',
                              child:
                                  Text('Day', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedType = val),
                      ),
                    ),
                  ),
                // Clear Readings button
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded, size: 20, color: Colors.red),
                  tooltip: 'Clear All Readings for this Device',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear All Readings'),
                        content: Text('Are you sure you want to delete ALL readings for ${widget.deviceName}? This cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(supabaseReadingsRepoProvider).deleteByDeviceId(widget.deviceId);
                      ref.invalidate(adminReadingsProvider);
                    }
                  },
                ),
              ],
            ),
          ),

          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No readings match the selected filter.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            // Calculated table with operator column
            ReadingsCalculatedTable(
              readings: plainReadings,
              matrixUnits: widget.matrixUnits,
              showTypeColumn: widget.showTypeColumn,
              heatUnitFactors: widget.heatUnitFactors,
              dayUnitFactors: widget.dayUnitFactors,
              showOperatorColumn: true,
              operatorNames: opNamesFiltered,
              showAdminActions: true,
            ),
        ],
      ),
    );
  }
}
