import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_date_utils.dart';
import '../../../../core/utils/reading_calculation_utils.dart';
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
                    diffs[u] = ReadingCalculationUtils.calculateDifference(curVals[u]!, prevVals[u]!);
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

class _SummaryTableView extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<_SummaryTableView> createState() => _SummaryTableViewState();
}

class _SummaryTableViewState extends ConsumerState<_SummaryTableView> {
  bool _cellSelectMode = false;
  // Map of cellKey -> {row, col, value, label}
  final Map<String, ({int row, int col, String value, String label})> _selectedCells = {};

  static const double _fixedW = 80.0;
  static const double _subHeatW = 55.0;
  static const double _subTimeW = 70.0;
  static const double _subValW = 75.0;
  static const double _subActW = 60.0;
  static const double _deviceBlockW = _subHeatW + _subTimeW + _subValW * 2 + _subActW + 4;

  static Widget _divV() => Container(width: 1, color: Colors.grey.withOpacity(0.2));
  static Widget _divH() => Divider(height: 1, color: Colors.grey.withOpacity(0.2));

  String _consStr(String readingId, String unit, String deviceId) {
    final diffs = widget.diffMap[readingId];
    if (diffs == null) return '—';
    final diff = diffs[unit];
    if (diff == null) return '—';
    final mf = widget.deviceFactors[deviceId]?[unit] ?? 1.0;
    final cons = diff * mf;
    return NumberFormat('#,##0.##').format(cons);
  }

  void _copySingle(String text) {
    if (text.trim().isEmpty || text == '—') return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.copy_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Copied "$text" to clipboard (Ready for Excel)')),
          ],
        ),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copySelectedAsColumn() {
    if (_selectedCells.isEmpty) return;
    final sorted = _selectedCells.values.toList()
      ..sort((a, b) {
        final rowCmp = a.row.compareTo(b.row);
        if (rowCmp != 0) return rowCmp;
        return a.col.compareTo(b.col);
      });

    final text = sorted.map((c) => c.value == '—' ? '' : c.value).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.table_chart_rounded, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${sorted.length} values copied as 1 Vertical Column (Paste in Excel)')),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copySelectedAsGrid() {
    if (_selectedCells.isEmpty) return;
    final sorted = _selectedCells.values.toList()
      ..sort((a, b) {
        final rowCmp = a.row.compareTo(b.row);
        if (rowCmp != 0) return rowCmp;
        return a.col.compareTo(b.col);
      });

    // Group by row
    final Map<int, List<({int row, int col, String value, String label})>> rowMap = {};
    for (final item in sorted) {
      rowMap.putIfAbsent(item.row, () => []).add(item);
    }

    final StringBuffer buffer = StringBuffer();
    for (final r in rowMap.keys.toList()..sort()) {
      final cols = rowMap[r]!..sort((a, b) => a.col.compareTo(b.col));
      buffer.writeln(cols.map((c) => c.value == '—' ? '' : c.value).join('\t'));
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.grid_on_rounded, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${sorted.length} cells copied as Grid (Tab-separated for Excel)')),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildInteractiveCell({
    required String cellKey,
    required int row,
    required int col,
    required String text,
    required String label,
    double width = 100.0,
    Color? textColor,
    Color? bg,
  }) {
    final isSelected = _selectedCells.containsKey(cellKey);

    final effectiveBg = isSelected
        ? AppColors.primaryContainer.withOpacity(0.65)
        : bg;

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _cellSelectMode = true;
          _selectedCells[cellKey] = (row: row, col: col, value: text, label: label);
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cell selected. Tap more cells to add to selection or tap Copy.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      onTap: () {
        setState(() {
          _cellSelectMode = true;
          if (_selectedCells.containsKey(cellKey)) {
            _selectedCells.remove(cellKey);
          } else {
            _selectedCells[cellKey] = (row: row, col: col, value: text, label: label);
          }
        });
      },
      child: Tooltip(
        message: isSelected ? 'Selected (Tap to deselect)' : 'Tap to select for Excel copy',
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          width: width,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.28) : bg,
            border: isSelected
                ? Border.all(color: Colors.blueAccent, width: 2.0)
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? Colors.blue.shade900 : textColor,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  static Widget _hCell(
    String text, {
    double width = 100.0,
    Color? bg,
    bool bold = true,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final child = Container(
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

    if (onTap == null) return child;

    return Tooltip(
      message: tooltip ?? 'Click to select column',
      child: InkWell(
        onTap: onTap,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerBg = theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final deviceHeaderBg = AppColors.primaryContainer.withOpacity(0.4);
    final isHeat = widget.showHeatNumber;

    const double daySubValW = 75.0;
    const double daySubActW = 60.0;
    const double dayDeviceBlockW = daySubValW * 2 + daySubActW + 2;

    final deviceBlockW = isHeat ? _deviceBlockW : dayDeviceBlockW;

    final List<_GroupedHeatRow> groupedHeatRows = [];
    final Map<int, Map<String, SupabaseReadingWithDetails>> groupedDayRows = {};

    if (isHeat) {
      final Map<String, List<SupabaseReadingWithDetails>> deviceReadingsMap = {};
      for (final rwd in widget.rows) {
        deviceReadingsMap.putIfAbsent(rwd.reading.deviceId, () => []).add(rwd);
      }

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

      groupedHeatRows.sort((a, b) {
        final dayCmp = b.businessDayMidnightMs.compareTo(a.businessDayMidnightMs);
        if (dayCmp != 0) return dayCmp;
        return b.sequenceIndex.compareTo(a.sequenceIndex);
      });
    } else {
      for (final rwd in widget.rows) {
        final bizDay = AppDateUtils.toBusinessDayMidnightUtcMs(rwd.reading.readingDate);
        groupedDayRows.putIfAbsent(bizDay, () => {})[rwd.reading.deviceId] = rwd;
      }
    }

    final sortedDayKeys = groupedDayRows.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Selection & Export Action Bar (Always visible)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                icon: Icon(_cellSelectMode ? Icons.close_rounded : Icons.crop_free_rounded, size: 16),
                label: Text(
                  _cellSelectMode ? 'Done Selecting' : '📋 Select Cells (Excel)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  backgroundColor: _cellSelectMode ? AppColors.primaryContainer : null,
                ),
                onPressed: () {
                  setState(() {
                    _cellSelectMode = !_cellSelectMode;
                    if (!_cellSelectMode) _selectedCells.clear();
                  });
                },
              ),
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
                    devices: widget.qualifiedDevices,
                    readings: widget.rows,
                    diffMap: widget.diffMap,
                    deviceFactors: widget.deviceFactors,
                  );

                  if (filePath != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Excel saved to: $filePath'),
                        duration: const Duration(seconds: 10),
                        action: SnackBarAction(
                          label: 'OPEN FILE',
                          onPressed: () => OpenFilex.open(filePath),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),

        // Prominent Floating / Active Copy Action Bar when cells are selected
        if (_selectedCells.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedCells.length} cells selected',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _selectedCells.clear()),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text('Copy (${_selectedCells.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: _copySelectedAsColumn,
                    ),
                  ],
                ),
              ],
            ),
          ),

        // Scrollable Table with Gesture Drag Support
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
                    // Header Row 1: Device Spanning Headers
                    Row(children: [
                      _hCell('Date', width: _fixedW, bg: headerBg),
                      ...widget.qualifiedDevices.expand((d) => [
                        _divV(),
                        Container(
                          width: deviceBlockW,
                          height: 34,
                          alignment: Alignment.center,
                          color: deviceHeaderBg,
                          child: Text(
                            widget.deviceNames[d.id] ?? d.id,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ]),

                    _divH(),

                    // Header Row 2: Sub-column Headers
                    Row(children: [
                      _hCell('', width: _fixedW, bg: headerBg),
                      ...widget.qualifiedDevices.asMap().entries.expand((entry) {
                        final devIdx = entry.key;
                        final d = entry.value;
                        final devName = widget.deviceNames[d.id] ?? d.id;

                        void selectFullColumn(String colType, int colOffset) {
                          final List<String> collectedValues = [];
                          setState(() {
                            _cellSelectMode = true;
                            if (isHeat) {
                              for (int rIdx = 0; rIdx < groupedHeatRows.length; rIdx++) {
                                final gr = groupedHeatRows[rIdx];
                                final rwd = gr.deviceReadings[d.id];
                                if (rwd != null) {
                                  String val = '';
                                  if (colType == 'heat') val = rwd.reading.heatNumber;
                                  if (colType == 'time') {
                                    val = DateFormat('hh:mm a').format(
                                      DateTime.fromMillisecondsSinceEpoch(rwd.reading.readingDate, isUtc: true).toLocal(),
                                    );
                                  }
                                  if (colType == 'kwh') val = _consStr(rwd.reading.id, 'KWH', d.id);
                                  if (colType == 'kwhlt') val = _consStr(rwd.reading.id, 'KWHLT', d.id);
                                  final key = 'h_${rIdx}_${devIdx}_$colOffset';
                                  _selectedCells[key] = (row: rIdx, col: devIdx * 5 + colOffset, value: val, label: '$devName $colType');
                                  if (val.isNotEmpty && val != '—') collectedValues.add(val);
                                }
                              }
                            } else {
                              for (int rIdx = 0; rIdx < sortedDayKeys.length; rIdx++) {
                                final day = sortedDayKeys[rIdx];
                                final rwd = groupedDayRows[day]?[d.id];
                                if (rwd != null) {
                                  String val = '';
                                  if (colType == 'kwh') val = _consStr(rwd.reading.id, 'KWH', d.id);
                                  if (colType == 'kwhlt') val = _consStr(rwd.reading.id, 'KWHLT', d.id);
                                  final key = 'd_${rIdx}_${devIdx}_$colOffset';
                                  _selectedCells[key] = (row: rIdx, col: devIdx * 2 + colOffset, value: val, label: '$devName $colType');
                                  if (val.isNotEmpty && val != '—') collectedValues.add(val);
                                }
                              }
                            }
                          });

                          if (collectedValues.isNotEmpty) {
                            Clipboard.setData(ClipboardData(text: collectedValues.join('\n')));
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.table_rows_rounded, color: Colors.greenAccent, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('${collectedValues.length} values for "$devName $colType" copied as 1 Vertical Column (Ready for Excel)')),
                                  ],
                                ),
                                duration: const Duration(seconds: 3),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }

                        if (isHeat) {
                          return [
                            _divV(),
                            _hCell('Heat #', width: _subHeatW, bg: deviceHeaderBg.withOpacity(0.5), onTap: () => selectFullColumn('heat', 1), tooltip: 'Click to select all Heat # values for $devName'),
                            _divV(),
                            _hCell('Time', width: _subTimeW, bg: deviceHeaderBg.withOpacity(0.5), onTap: () => selectFullColumn('time', 2), tooltip: 'Click to select all Time values for $devName'),
                            _divV(),
                            _hCell('KWH', width: _subValW, bg: deviceHeaderBg.withOpacity(0.5), onTap: () => selectFullColumn('kwh', 3), tooltip: 'Click to select all KWH values for $devName'),
                            _divV(),
                            _hCell('KWHLT', width: _subValW, bg: deviceHeaderBg.withOpacity(0.5), onTap: () => selectFullColumn('kwhlt', 4), tooltip: 'Click to select all KWHLT values for $devName'),
                            _divV(),
                            _hCell('Act', width: _subActW, bg: deviceHeaderBg.withOpacity(0.5)),
                          ];
                        }

                        return [
                          _divV(),
                          _hCell('KWH', width: daySubValW, bg: deviceHeaderBg.withOpacity(0.5), onTap: () => selectFullColumn('kwh', 1), tooltip: 'Click to select all KWH values for $devName'),
                          _divV(),
                          _hCell('KWHLT', width: daySubValW, bg: deviceHeaderBg.withOpacity(0.5), onTap: () => selectFullColumn('kwhlt', 2), tooltip: 'Click to select all KWHLT values for $devName'),
                          _divV(),
                          _hCell('Act', width: daySubActW, bg: deviceHeaderBg.withOpacity(0.5)),
                        ];
                      }),
                    ]),

                    _divH(),

                    // Data rows
                    if (isHeat)
                      ...groupedHeatRows.asMap().entries.map((entry) {
                        final rIdx = entry.key;
                        final gr = entry.value;
                        final dateStr = DateFormat('dd MMM yy').format(
                          DateTime.fromMillisecondsSinceEpoch(gr.businessDayMidnightMs, isUtc: true).toLocal(),
                        );

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              _buildInteractiveCell(
                                cellKey: 'date_$rIdx',
                                row: rIdx,
                                col: 0,
                                text: dateStr,
                                label: 'Date',
                                width: _fixedW,
                              ),
                              ...widget.qualifiedDevices.asMap().entries.expand((devEntry) {
                                final devIdx = devEntry.key;
                                final d = devEntry.value;
                                final devName = widget.deviceNames[d.id] ?? d.id;
                                final rwd = gr.deviceReadings[d.id];

                                if (rwd == null) {
                                  return [
                                    _divV(),
                                    _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_1', row: rIdx, col: devIdx * 5 + 1, text: '—', label: '$devName Heat', width: _subHeatW),
                                    _divV(),
                                    _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_2', row: rIdx, col: devIdx * 5 + 2, text: '—', label: '$devName Time', width: _subTimeW),
                                    _divV(),
                                    _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_3', row: rIdx, col: devIdx * 5 + 3, text: '—', label: '$devName KWH', width: _subValW),
                                    _divV(),
                                    _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_4', row: rIdx, col: devIdx * 5 + 4, text: '—', label: '$devName KWHLT', width: _subValW),
                                    _divV(),
                                    const SizedBox(width: _subActW, height: 38, child: Center(child: Text('—', style: TextStyle(fontSize: 11)))),
                                  ];
                                }

                                final r = rwd.reading;
                                final readingTimeStr = DateFormat('hh:mm a').format(
                                  DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal(),
                                );
                                final kwhStr = _consStr(r.id, 'KWH', d.id);
                                final kwhltStr = _consStr(r.id, 'KWHLT', d.id);

                                return [
                                  _divV(),
                                  _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_1', row: rIdx, col: devIdx * 5 + 1, text: r.heatNumber, label: '$devName Heat', width: _subHeatW),
                                  _divV(),
                                  _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_2', row: rIdx, col: devIdx * 5 + 2, text: readingTimeStr, label: '$devName Time', width: _subTimeW),
                                  _divV(),
                                  _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_3', row: rIdx, col: devIdx * 5 + 3, text: kwhStr, label: '$devName KWH', width: _subValW),
                                  _divV(),
                                  _buildInteractiveCell(cellKey: 'h_${rIdx}_${devIdx}_4', row: rIdx, col: devIdx * 5 + 4, text: kwhltStr, label: '$devName KWHLT', width: _subValW),
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
                      ...sortedDayKeys.asMap().entries.map((entry) {
                        final rIdx = entry.key;
                        final day = entry.value;
                        final dateStr = DateFormat('dd MMM yy').format(
                          DateTime.fromMillisecondsSinceEpoch(day, isUtc: true).toLocal(),
                        );

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              _buildInteractiveCell(
                                cellKey: 'date_$rIdx',
                                row: rIdx,
                                col: 0,
                                text: dateStr,
                                label: 'Date',
                                width: _fixedW,
                              ),
                              ...widget.qualifiedDevices.asMap().entries.expand((devEntry) {
                                final devIdx = devEntry.key;
                                final d = devEntry.value;
                                final devName = widget.deviceNames[d.id] ?? d.id;
                                final rwd = groupedDayRows[day]?[d.id];

                                if (rwd == null) {
                                  return [
                                    _divV(),
                                    _buildInteractiveCell(cellKey: 'd_${rIdx}_${devIdx}_1', row: rIdx, col: devIdx * 2 + 1, text: '—', label: '$devName KWH', width: daySubValW),
                                    _divV(),
                                    _buildInteractiveCell(cellKey: 'd_${rIdx}_${devIdx}_2', row: rIdx, col: devIdx * 2 + 2, text: '—', label: '$devName KWHLT', width: daySubValW),
                                    _divV(),
                                    const SizedBox(width: daySubActW, height: 38, child: Center(child: Text('—', style: TextStyle(fontSize: 11)))),
                                  ];
                                }

                                final r = rwd.reading;
                                final kwhStr = _consStr(r.id, 'KWH', d.id);
                                final kwhltStr = _consStr(r.id, 'KWHLT', d.id);

                                return [
                                  _divV(),
                                  _buildInteractiveCell(cellKey: 'd_${rIdx}_${devIdx}_1', row: rIdx, col: devIdx * 2 + 1, text: kwhStr, label: '$devName KWH', width: daySubValW),
                                  _divV(),
                                  _buildInteractiveCell(cellKey: 'd_${rIdx}_${devIdx}_2', row: rIdx, col: devIdx * 2 + 2, text: kwhltStr, label: '$devName KWHLT', width: daySubValW),
                                  _divV(),
                                  SizedBox(
                                    width: daySubActW,
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
