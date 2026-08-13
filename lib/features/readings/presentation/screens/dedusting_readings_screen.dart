import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../notifiers/admin_readings_notifier.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

class _DedFilter {
  const _DedFilter({this.operatorId, this.fromDateMs, this.toDateMs});
  final String? operatorId;
  final int? fromDateMs;
  final int? toDateMs;
}

final _dedFilterProvider =
    StateProvider<_DedFilter>((ref) => const _DedFilter());

final _dedReadingsProvider =
    FutureProvider.autoDispose<List<SupabaseReadingWithDetails>>((ref) {
  final filter = ref.watch(_dedFilterProvider);
  final repo   = ref.watch(supabaseReadingsRepoProvider);
  return repo.search(
    operatorId: filter.operatorId,
    fromDateMs: filter.fromDateMs,
    toDateMs:   filter.toDateMs,
    limit: 500,
  ).then((all) => all.where((r) => r.isDedusting).toList());
});

// ── Screen ────────────────────────────────────────────────────────────────────

class DeddustingReadingsScreen extends ConsumerStatefulWidget {
  const DeddustingReadingsScreen({super.key});

  @override
  ConsumerState<DeddustingReadingsScreen> createState() =>
      _DeddustingReadingsScreenState();
}

class _DeddustingReadingsScreenState
    extends ConsumerState<DeddustingReadingsScreen> {
  DateTimeRange? _dateRange;

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (picked == null) return;
    setState(() => _dateRange = picked);
    ref.read(_dedFilterProvider.notifier).update((s) => _DedFilter(
          operatorId: s.operatorId,
          fromDateMs: picked.start.millisecondsSinceEpoch,
          toDateMs:   picked.end
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ));
  }

  void _clearFilters() {
    setState(() => _dateRange = null);
    ref.read(_dedFilterProvider.notifier).state = const _DedFilter();
  }

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final readingsAsync = ref.watch(_dedReadingsProvider);
    final filter     = ref.watch(_dedFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dedusting Sheet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.go(RoutePaths.adminDashboard),
        ),
      ),
      body: Column(
        children: [
          // ── Filter bar ─────────────────────────────────────────────
          _DedFilterBar(
            dateRange:  _dateRange,
            operatorId: filter.operatorId,
            onDateTap:  _pickDateRange,
            onOperatorChanged: (id) {
              ref.read(_dedFilterProvider.notifier).update((s) =>
                  _DedFilter(
                    operatorId: id,
                    fromDateMs: s.fromDateMs,
                    toDateMs:   s.toDateMs,
                  ));
            },
            onClear: _clearFilters,
          ),
          // ── Content ────────────────────────────────────────────────
          Expanded(
            child: readingsAsync.when(
              loading: () =>
                  const LoadingWidget(message: 'Loading dedusting readings…'),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (readings) {
                if (readings.isEmpty) {
                  return const EmptyStateWidget(
                    icon: Icons.air_rounded,
                    title: 'No Dedusting Readings',
                    subtitle:
                        'Submit readings from the Operator app to see data here.',
                  );
                }
                return _DedSheetBody(readings: readings, theme: theme);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter bar widget ─────────────────────────────────────────────────────────

class _DedFilterBar extends ConsumerWidget {
  const _DedFilterBar({
    required this.dateRange,
    required this.operatorId,
    required this.onDateTap,
    required this.onOperatorChanged,
    required this.onClear,
  });

  final DateTimeRange? dateRange;
  final String? operatorId;
  final VoidCallback onDateTap;
  final ValueChanged<String?> onOperatorChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opsAsync = ref.watch(allOperatorsProvider);
    final fmt = DateFormat('dd MMM');
    final hasFilter = dateRange != null || operatorId != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Row(
        children: [
          // Date range chip
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDateTap,
              icon: const Icon(Icons.date_range_rounded, size: 16),
              label: Text(
                dateRange == null
                    ? 'All Dates'
                    : '${fmt.format(dateRange!.start)} – ${fmt.format(dateRange!.end)}',
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Operator dropdown
          Expanded(
            child: opsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (ops) => DropdownButtonFormField<String?>(
                value: operatorId,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: 'All Operators',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Operators')),
                  ...ops.map((op) => DropdownMenuItem(
                        value: op.id,
                        child: Text(op.fullName ?? op.username,
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: onOperatorChanged,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 20),
              tooltip: 'Clear Filters',
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sheet body: operator-grouped, columnar table ──────────────────────────────

class _DedSheetBody extends StatelessWidget {
  const _DedSheetBody({required this.readings, required this.theme});

  final List<SupabaseReadingWithDetails> readings;
  final ThemeData theme;

  static const _labelW = 90.0;
  static const _cellW  = 100.0;

  static Map<String, double> _parseVals(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group by operator
    final Map<String, List<SupabaseReadingWithDetails>> byOp = {};
    for (final r in readings) {
      byOp.putIfAbsent(r.operatorName, () => []).add(r);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: byOp.entries.map((opEntry) {
        final opName    = opEntry.key;
        final opReadings = opEntry.value;

        // Group by device within this operator
        final Map<String, List<SupabaseReadingWithDetails>> byDevice = {};
        for (final r in opReadings) {
          byDevice.putIfAbsent(r.deviceName, () => []).add(r);
        }

        // Sort devices by name
        final deviceNames = byDevice.keys.toList()..sort();

        // Collect all unique dates across all devices, sorted ascending
        final allDatesMs = <int>{};
        for (final devReadings in byDevice.values) {
          for (final r in devReadings) {
            allDatesMs.add(r.reading.readingDate);
          }
        }
        final sortedDates = allDatesMs.toList()..sort();

        // Build diff/consumption per device per date
        // For each device: sort by date asc, compute diff from previous row
        final Map<String, Map<int, Map<String, double?>>> devDateData = {};
        for (final devName in deviceNames) {
          final devRwds = byDevice[devName]!
            ..sort((a, b) =>
                a.reading.readingDate.compareTo(b.reading.readingDate));
          final dateMap = <int, Map<String, double?>>{};
          for (int i = 0; i < devRwds.length; i++) {
            final cur    = devRwds[i];
            final vals   = _parseVals(cur.reading.readingValues);
            final metric = cur.reading.deviceId.isEmpty ? 'KWH' : 'KWH';
            final mf     = cur.deviceMf;
            final reading = vals[metric] ?? vals.values.firstOrNull;

            double? diff;
            double? consumption;
            if (i > 0) {
              final prevVals =
                  _parseVals(devRwds[i - 1].reading.readingValues);
              final prev = prevVals[metric] ?? prevVals.values.firstOrNull;
              if (reading != null && prev != null) {
                diff        = reading - prev;
                consumption = diff * mf;
              }
            }
            dateMap[cur.reading.readingDate] = {
              'reading':     reading,
              'diff':        diff,
              'consumption': consumption,
            };
          }
          devDateData[devName] = dateMap;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Operator header ───────────────────────────────────
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.primary.withOpacity(0.15),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      opName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              // ── Horizontal scrollable table ───────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildTable(
                  deviceNames:  deviceNames,
                  sortedDates:  sortedDates,
                  devDateData:  devDateData,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTable({
    required List<String> deviceNames,
    required List<int> sortedDates,
    required Map<String, Map<int, Map<String, double?>>> devDateData,
  }) {
    final dateFmt = DateFormat('dd MMM');
    final numFmt  = NumberFormat('#,##0.##');

    // Header row 1: device names spanning 3 columns each
    // Header row 2: Reading | Diff | Consumption per device

    Widget hCell(String text, {double width = _cellW, Color? bg, bool bold = true}) =>
        Container(
          width: width,
          height: 34,
          alignment: Alignment.center,
          color: bg,
          child: Text(
            text,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        );

    Widget dCell(String text, {double width = _cellW, Color? textColor}) =>
        Container(
          width: width,
          height: 36,
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: textColor),
            textAlign: TextAlign.center,
          ),
        );

    final divider = Container(height: 1, color: Colors.grey.shade200);
    final headerBg = AppColors.secondary.withOpacity(0.12);
    final subHeaderBg = AppColors.secondary.withOpacity(0.06);

    return Table(
      defaultColumnWidth: const FixedColumnWidth(_cellW),
      columnWidths: {
        0: const FixedColumnWidth(_labelW),
        for (int i = 0; i < deviceNames.length * 3; i++)
          i + 1: const FixedColumnWidth(_cellW),
      },
      border: TableBorder(
        verticalInside: BorderSide(color: Colors.grey.shade200, width: 0.5),
      ),
      children: [
        // ── Row 1: Equipment name headers ───────────────
        TableRow(
          children: [
            hCell('Date', width: _labelW, bg: headerBg),
            for (final devName in deviceNames) ...[
              Container(
                width: _cellW * 3,
                height: 34,
                alignment: Alignment.center,
                color: headerBg,
                child: Text(
                  devName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // two spacer cells (colspan workaround in Table)
              hCell('', width: _cellW, bg: headerBg),
              hCell('', width: _cellW, bg: headerBg),
            ],
          ],
        ),
        // ── Row 2: Sub-headers: Reading / Diff / Consumption ─
        TableRow(
          children: [
            hCell('', width: _labelW, bg: subHeaderBg),
            for (int _ = 0; _ < deviceNames.length; _++) ...[
              hCell('Reading', bg: subHeaderBg),
              hCell('Diff', bg: subHeaderBg),
              hCell('KWH', bg: subHeaderBg),
            ],
          ],
        ),
        // ── Data rows: one per date ──────────────────────
        for (int di = 0; di < sortedDates.length; di++) ...[
          TableRow(
            decoration: BoxDecoration(
              color: di.isOdd ? Colors.grey.shade50 : Colors.white,
            ),
            children: [
              dCell(dateFmt.format(
                DateTime.fromMillisecondsSinceEpoch(sortedDates[di]))),
              for (final devName in deviceNames) ...[
                // Reading
                dCell(
                  () {
                    final d = devDateData[devName]?[sortedDates[di]];
                    final v = d?['reading'];
                    return v == null ? '\u2014' : numFmt.format(v);
                  }(),
                ),
                // Diff
                dCell(
                  () {
                    final d = devDateData[devName]?[sortedDates[di]];
                    final v = d?['diff'];
                    if (v == null) return '\u2014';
                    return v < 0
                        ? '\u25bc ${numFmt.format(v.abs())}'
                        : numFmt.format(v);
                  }(),
                  textColor: () {
                    final d = devDateData[devName]?[sortedDates[di]];
                    final v = d?['diff'];
                    if (v == null) return null;
                    return v < 0 ? Colors.red : Colors.green.shade700;
                  }(),
                ),
                // Consumption
                dCell(
                  () {
                    final d = devDateData[devName]?[sortedDates[di]];
                    final v = d?['consumption'];
                    return v == null ? '\u2014' : numFmt.format(v);
                  }(),
                  textColor: AppColors.primary,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}
