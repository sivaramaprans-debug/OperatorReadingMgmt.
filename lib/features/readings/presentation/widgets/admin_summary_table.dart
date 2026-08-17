import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../routing/route_paths.dart';
import '../../../../shared/widgets/loading_widget.dart';
import '../../../../shared/widgets/empty_state_widget.dart';
import '../../domain/usecases/export_readings_usecase.dart';
import '../notifiers/admin_readings_notifier.dart';

/// Summary table displayed in the Admin panel.
/// [readingType] = 'day' or 'heat'
/// Columns = devices (that have KWH or KWHLT in the relevant matrix).
/// Rows    = individual readings sorted newest first.
/// Values  = Consumption of KWH and KWHLT (Difference × per-unit MF).
class AdminSummaryTable extends ConsumerWidget {
  const AdminSummaryTable({super.key, required this.readingType});
  final String readingType; // 'day' or 'heat'

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingsAsync = ref.watch(
      readingType == 'heat'
          ? adminHeatSummaryReadingsProvider
          : adminDaySummaryReadingsProvider,
    );
    final devicesAsync = ref.watch(allDevicesProvider);
    final filter = ref.watch(adminReadingsFilterProvider);
    final selectedOperatorId = filter.operatorId;

    return readingsAsync.when(
      loading: () => const LoadingWidget(message: 'Loading summary...'),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (allReadings) => devicesAsync.when(
        loading: () => const LoadingWidget(message: 'Loading devices...'),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allDevices) {
          // Filter readings by type from the full set
          final typeReadings = allReadings
              .where((rwd) => rwd.reading.readingType == readingType)
              .toList()
            ..sort((a, b) => b.reading.readingDate.compareTo(a.reading.readingDate));

          if (typeReadings.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.table_chart_outlined,
              title: 'No ${readingType == 'day' ? 'Day' : 'Heat'} Readings',
              subtitle: 'No readings found for this type.',
            );
          }

          // Build qualified devices ONLY from device IDs that appear
          // in the reading rows of this type — prevents empty columns.
          final deviceIdsInRows = typeReadings.map((r) => r.reading.deviceId).toSet();
          final qualifiedDevices = allDevices.where((d) {
            if (!deviceIdsInRows.contains(d.id)) return false;
            if (readingType == 'heat' && !d.requiresHeatDay) return false;
            final matrixStr = readingType == 'heat' ? d.matrix : d.dayMatrix;
            return matrixStr.trim().isNotEmpty;
          }).toList();

          if (qualifiedDevices.isEmpty) {
            return EmptyStateWidget(
              icon: Icons.devices_other_rounded,
              title: 'No Qualifying Devices',
              subtitle: readingType == 'heat'
                  ? 'No heat-enabled devices found.'
                  : 'No devices found with day matrix.',
            );
          }

          // Build device factor maps
          final deviceFactors = <String, Map<String, double>>{};
          for (final d in qualifiedDevices) {
            final factorJson = readingType == 'heat' ? d.heatUnitFactors : d.dayUnitFactors;
            deviceFactors[d.id] = _parseFactors(factorJson);
          }

          // Build device name map
          final deviceNames = {for (final d in qualifiedDevices) d.id: d.name};

          // Group ALL readings of this type by deviceId for true chronological diff calculation
          final readingsByDevice = <String, List<SupabaseReadingWithDetails>>{};
          for (final rwd in allReadings) {
            if (rwd.reading.readingType == readingType) {
              readingsByDevice.putIfAbsent(rwd.reading.deviceId, () => []).add(rwd);
            }
          }

          // Compute differences per device (sorted oldest→newest for calculation)
          final diffMap = <String, Map<String, double?>>{};
          for (final deviceId in readingsByDevice.keys) {
            final deviceRows = List<SupabaseReadingWithDetails>.from(readingsByDevice[deviceId]!);
            deviceRows.sort((a, b) {
              final dateCmp = a.reading.readingDate.compareTo(b.reading.readingDate);
              if (dateCmp != 0) return dateCmp;
              final createdCmp = a.reading.createdAt.compareTo(b.reading.createdAt);
              if (createdCmp != 0) return createdCmp;
              final ha = int.tryParse(a.reading.heatNumber) ?? 0;
              final hb = int.tryParse(b.reading.heatNumber) ?? 0;
              return ha.compareTo(hb);
            });

            for (int i = 0; i < deviceRows.length; i++) {
              final cur = deviceRows[i];
              final curVals = _parseValues(cur.reading.readingValues);
              final diffs = <String, double?>{};
              if (i == 0) {
                diffs['KWH'] = null;
                diffs['KWHLT'] = null;
              } else {
                final prevVals = _parseValues(deviceRows[i - 1].reading.readingValues);
                for (final u in ['KWH', 'KWHLT']) {
                  if (curVals.containsKey(u) && prevVals.containsKey(u)) {
                    diffs[u] = curVals[u]! - prevVals[u]!;
                  } else {
                    diffs[u] = null;
                  }
                }
              }
              diffMap[cur.reading.id] = diffs;
            }
          }

          // Now filter the rows to display in the UI based on the selected operator filter
          final filteredRows = selectedOperatorId == null
              ? typeReadings
              : typeReadings.where((rwd) => rwd.reading.operatorId == selectedOperatorId).toList();

          return _SummaryTableView(
            rows: filteredRows,
            qualifiedDevices: qualifiedDevices,
            deviceNames: deviceNames,
            deviceFactors: deviceFactors,
            diffMap: diffMap,
            showHeatNumber: readingType == 'heat',
          );
        },
      ),
    );
  }

  static Map<String, double> _parseFactors(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  static Map<String, double> _parseValues(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }
}

class _GroupedHeatRow {
  final int businessDayMidnightMs;
  final int sequenceIndex;
  final Map<String, SupabaseReadingWithDetails> deviceReadings;

  _GroupedHeatRow({
    required this.businessDayMidnightMs,
    required this.sequenceIndex,
    required this.deviceReadings,
  });
}

class _SummaryTableView extends ConsumerWidget {
  const _SummaryTableView({
    required this.rows,
    required this.qualifiedDevices,
    required this.deviceNames,
    required this.deviceFactors,
    required this.diffMap,
    required this.showHeatNumber,
  });

  final List<SupabaseReadingWithDetails> rows;
  final List<SupabaseDevice> qualifiedDevices;
  final Map<String, String> deviceNames;
  final Map<String, Map<String, double>> deviceFactors;
  final Map<String, Map<String, double?>> diffMap;
  final bool showHeatNumber;

  static const double _fixedW = 80.0;

  // Sub-widths for Heat Summary device blocks
  static const double _subHeatW = 55.0;
  static const double _subTimeW = 70.0;
  static const double _subValW = 75.0;
  static const double _subActW = 60.0;
  static const double _deviceBlockW = _subHeatW + _subTimeW + _subValW * 2 + _subActW + 4; // Includes dividers

  static Widget _hCell(String text, {double width = 100.0, Color? bg, bool bold = true}) =>
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

  static Widget _dCell(String text, {double width = 100.0, Color? textColor}) =>
      Container(
        width: width,
        height: 38,
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: textColor),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      );

  static Widget _divV() => Container(width: 1, color: Colors.grey.withOpacity(0.2));
  static Widget _divH() => Divider(height: 1, color: Colors.grey.withOpacity(0.2));

  String _consStr(String readingId, String unit, String deviceId) {
    final diffs = diffMap[readingId];
    if (diffs == null) return '—';
    final diff = diffs[unit];
    if (diff == null) return '—';
    final mf = deviceFactors[deviceId]?[unit] ?? 1.0;
    final cons = diff * mf;
    return NumberFormat('#,##0.##').format(cons);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final headerBg = theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final deviceHeaderBg = AppColors.primaryContainer.withOpacity(0.4);

    final isHeat = showHeatNumber;

    // Sub-widths for Day Summary device blocks (KWH, KWHLT, Act)
    const double daySubValW = 75.0;
    const double daySubActW = 60.0;
    const double dayDeviceBlockW = daySubValW * 2 + daySubActW + 2; // 212.0

    // Device block width depending on tab
    final deviceBlockW = isHeat ? _deviceBlockW : dayDeviceBlockW;

    // Grouping logic for Heat Summary
    final List<_GroupedHeatRow> groupedHeatRows = [];
    // Grouping logic for Day Summary (exactly one row per Business Day)
    final Map<int, Map<String, SupabaseReadingWithDetails>> groupedDayRows = {};

    if (isHeat) {
      // 1. Group readings by device
      final Map<String, List<SupabaseReadingWithDetails>> deviceReadingsMap = {};
      for (final rwd in rows) {
        deviceReadingsMap.putIfAbsent(rwd.reading.deviceId, () => []).add(rwd);
      }

      // 2. Sort readings for each device chronologically, and group them by 8 AM business day
      final Map<String, Map<int, List<SupabaseReadingWithDetails>>> deviceDayReadings = {};

      for (final devId in deviceReadingsMap.keys) {
        final devRwds = List<SupabaseReadingWithDetails>.from(deviceReadingsMap[devId]!)
          ..sort((a, b) => a.reading.readingDate.compareTo(b.reading.readingDate));

        final Map<int, List<SupabaseReadingWithDetails>> dayMap = {};
        for (final rwd in devRwds) {
          final bizDay = AppDateUtils.toBusinessDayMidnightUtcMs(rwd.reading.readingDate);
          dayMap.putIfAbsent(bizDay, () => []).add(rwd);
        }
        deviceDayReadings[devId] = dayMap;
      }

      // 3. Find the maximum sequenceIndex for each business day
      final Map<int, int> maxSeqPerDay = {};
      for (final dayMap in deviceDayReadings.values) {
        for (final entry in dayMap.entries) {
          final day = entry.key;
          final count = entry.value.length;
          final maxIndex = count - 1;
          final existingMax = maxSeqPerDay[day] ?? -1;
          if (maxIndex > existingMax) {
            maxSeqPerDay[day] = maxIndex;
          }
        }
      }

      // 4. Build the final _GroupedHeatRow list
      for (final day in maxSeqPerDay.keys) {
        final maxIndex = maxSeqPerDay[day]!;
        for (int seq = 0; seq <= maxIndex; seq++) {
          final Map<String, SupabaseReadingWithDetails> devMap = {};
          for (final devId in deviceDayReadings.keys) {
            final list = deviceDayReadings[devId]?[day];
            if (list != null && seq < list.length) {
              devMap[devId] = list[seq];
            }
          }
          groupedHeatRows.add(_GroupedHeatRow(
            businessDayMidnightMs: day,
            sequenceIndex: seq,
            deviceReadings: devMap,
          ));
        }
      }

      // Sort: businessDayMidnightMs descending, sequenceIndex descending
      groupedHeatRows.sort((a, b) {
        final dayCmp = b.businessDayMidnightMs.compareTo(a.businessDayMidnightMs);
        if (dayCmp != 0) return dayCmp;
        return b.sequenceIndex.compareTo(a.sequenceIndex);
      });
    } else {
      // Day Summary: Group readings by Business Day only
      for (final rwd in rows) {
        final bizDay = AppDateUtils.toBusinessDayMidnightUtcMs(rwd.reading.readingDate);
        groupedDayRows.putIfAbsent(bizDay, () => {})[rwd.reading.deviceId] = rwd;
      }
    }

    final sortedDayKeys = groupedDayRows.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final totalDisplayRows = isHeat ? groupedHeatRows.length : sortedDayKeys.length;

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Export Header Bar
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  isHeat
                      ? 'Filtered Records (Grouped: $totalDisplayRows heats)'
                      : 'Filtered Records (Grouped: $totalDisplayRows days)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.table_view_rounded, size: 16),
                  label: const Text(
                    'Export Filtered Excel',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () async {
                    final exporter = ExportReadingsUseCase();
                    final filePath = await exporter.exportAdminSheetToExcel(
                      sheetTitle: isHeat ? 'Heat_Summary' : 'Day_Summary',
                      devices: qualifiedDevices,
                      readings: rows,
                      diffMap: diffMap,
                      deviceFactors: deviceFactors,
                    );

                    if (filePath != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Excel saved to: $filePath'),
                          duration: const Duration(seconds: 10),
                          action: SnackBarAction(
                            label: 'OPEN FILE',
                            onPressed: () {
                              OpenFilex.open(filePath);
                            },
                          ),
                        ),
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Export downloaded successfully.')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          Builder(
            builder: (context) {
              final scrollController = ScrollController();
              return Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                thickness: 8,
                child: SingleChildScrollView(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Row 1: Spanning headers ─────────────────────────────────
                      Row(children: [
                        _hCell('Date', width: _fixedW, bg: headerBg),
                        ...qualifiedDevices.expand((d) => [
                          _divV(),
                          Container(
                            width: deviceBlockW,
                            height: 34,
                            alignment: Alignment.center,
                            color: deviceHeaderBg,
                            child: Text(
                              deviceNames[d.id] ?? d.id,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ]),

                      _divH(),

                      // ── Row 2: Sub-column headers ───────────────────────────────
                      Row(children: [
                        _hCell('', width: _fixedW, bg: headerBg),
                        ...qualifiedDevices.expand((d) => [
                          _divV(),
                          if (isHeat) ...[
                            _hCell('Heat #', width: _subHeatW, bg: deviceHeaderBg.withOpacity(0.5)),
                            _divV(),
                            _hCell('Time', width: _subTimeW, bg: deviceHeaderBg.withOpacity(0.5)),
                            _divV(),
                          ],
                          _hCell('KWH', width: _subValW, bg: deviceHeaderBg.withOpacity(0.5)),
                          _divV(),
                          _hCell('KWHLT', width: _subValW, bg: deviceHeaderBg.withOpacity(0.5)),
                          _divV(),
                          _hCell('Act', width: _subActW, bg: deviceHeaderBg.withOpacity(0.5)),
                        ]),
                      ]),

                      _divH(),

                      // ── Data rows ────────────────────────────────────────────────
                      if (isHeat)
                        ...groupedHeatRows.map((gr) {
                          final dateStr = DateFormat('dd MMM yy').format(
                            DateTime.fromMillisecondsSinceEpoch(gr.businessDayMidnightMs, isUtc: true).toLocal(),
                          );

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(children: [
                                _dCell(dateStr, width: _fixedW),
                                ...qualifiedDevices.expand((d) {
                                  final rwd = gr.deviceReadings[d.id];
                                  if (rwd == null) {
                                    return [
                                      _divV(),
                                      _dCell('—', width: _subHeatW),
                                      _divV(),
                                      _dCell('—', width: _subTimeW),
                                      _divV(),
                                      _dCell('—', width: _subValW),
                                      _divV(),
                                      _dCell('—', width: _subValW),
                                      _divV(),
                                      const SizedBox(width: _subActW, height: 38, child: Center(child: Text('—', style: TextStyle(fontSize: 11)))),
                                    ];
                                  }

                                  final r = rwd.reading;
                                  final readingTimeStr = DateFormat('hh:mm a').format(
                                    DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal(),
                                  );

                                  return [
                                    _divV(),
                                    _dCell(r.heatNumber, width: _subHeatW),
                                    _divV(),
                                    _dCell(readingTimeStr, width: _subTimeW),
                                    _divV(),
                                    _dCell(_consStr(r.id, 'KWH', d.id), width: _subValW),
                                    _divV(),
                                    _dCell(_consStr(r.id, 'KWHLT', d.id), width: _subValW),
                                    _divV(),
                                    SizedBox(
                                      width: _subActW,
                                      height: 38,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_rounded, size: 14),
                                            onPressed: () {
                                              context.push(RoutePaths.adminReadingEditPath(r.id), extra: r);
                                            },
                                            tooltip: 'Edit',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_rounded, size: 14, color: Colors.red),
                                            onPressed: () => _deleteReading(context, ref, r.id),
                                            tooltip: 'Delete',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ];
                                }),
                              ]),
                              _divH(),
                            ],
                          );
                        })
                      else
                        ...sortedDayKeys.map((day) {
                          final dateStr = DateFormat('dd MMM yy').format(
                            DateTime.fromMillisecondsSinceEpoch(day, isUtc: true).toLocal(),
                          );

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(children: [
                                _dCell(dateStr, width: _fixedW),
                                ...qualifiedDevices.expand((d) {
                                  final rwd = groupedDayRows[day]?[d.id];
                                  if (rwd == null) {
                                    return [
                                      _divV(),
                                      _dCell('—', width: _subValW),
                                      _divV(),
                                      _dCell('—', width: _subValW),
                                      _divV(),
                                      const SizedBox(width: _subActW, height: 38, child: Center(child: Text('—', style: TextStyle(fontSize: 11)))),
                                    ];
                                  }

                                  final r = rwd.reading;

                                  return [
                                    _divV(),
                                    _dCell(_consStr(r.id, 'KWH', d.id), width: _subValW),
                                    _divV(),
                                    _dCell(_consStr(r.id, 'KWHLT', d.id), width: _subValW),
                                    _divV(),
                                    SizedBox(
                                      width: _subActW,
                                      height: 38,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_rounded, size: 14),
                                            onPressed: () {
                                              context.push(RoutePaths.adminReadingEditPath(r.id), extra: r);
                                            },
                                            tooltip: 'Edit',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_rounded, size: 14, color: Colors.red),
                                            onPressed: () => _deleteReading(context, ref, r.id),
                                            tooltip: 'Delete',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ];
                                }),
                              ]),
                              _divH(),
                            ],
                          );
                        }),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<void> _deleteReading(BuildContext context, WidgetRef ref, String readingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reading'),
        content: const Text('Are you sure you want to delete this reading?'),
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
      await ref.read(supabaseReadingsRepoProvider).delete(readingId);
      ref.invalidate(adminReadingsProvider);
      ref.invalidate(adminDaySummaryReadingsProvider);
      ref.invalidate(adminHeatSummaryReadingsProvider);
    }
  }
}
