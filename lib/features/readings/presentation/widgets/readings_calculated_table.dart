import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/reading_calculation_utils.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../routing/route_paths.dart';
import '../notifiers/admin_readings_notifier.dart';

/// A horizontally-scrollable table with two header rows per unit:
///   Row 1 — unit name spanning 3 sub-columns
///   Row 2 — Reading | Difference | Consumption
class ReadingsCalculatedTable extends ConsumerStatefulWidget {
  const ReadingsCalculatedTable({
    super.key,
    required this.readings,
    required this.matrixUnits,
    required this.showTypeColumn,
    required this.heatUnitFactors,
    required this.dayUnitFactors,
    this.showOperatorColumn = false,
    this.operatorNames = const {},
    this.showAdminActions = false,
    this.enableExcelCopyTools = false,
    this.filterOperatorId,
  });

  final List<SupabaseReading> readings;
  final List<String> matrixUnits;
  final bool showTypeColumn;
  final Map<String, double> heatUnitFactors;
  final Map<String, double> dayUnitFactors;
  final bool showOperatorColumn;
  final Map<String, String> operatorNames;
  final bool showAdminActions;
  final bool enableExcelCopyTools;
  final String? filterOperatorId;

  @override
  ConsumerState<ReadingsCalculatedTable> createState() => _ReadingsCalculatedTableState();
}

class _ReadingsCalculatedTableState extends ConsumerState<ReadingsCalculatedTable> {
  bool _selectionMode = false;
  bool _cellSelectMode = false;
  final Set<String> _selectedReadingIds = {};
  final Map<String, ({int row, int col, String value, String label})> _selectedCells = {};

  static bool _isCumulativeUnit(String unit) {
    final u = unit.trim().toUpperCase();
    return u == 'KWH' || u == 'KWHLT' || u == 'KVAH' || u == 'KVARH';
  }

  static bool _isMfUnit(String unit) {
    final u = unit.trim().toUpperCase();
    return u == 'MD';
  }

  static Map<String, double> _parseValues(String json) {
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Map<String, Map<String, double?>> _buildDifferenceMap() {
    final dayReadings = widget.readings
        .where((r) => r.readingType == 'day' || r.readingType == 'standard')
        .toList()
      ..sort((a, b) => a.readingDate.compareTo(b.readingDate));

    final heatReadings = widget.readings.where((r) => r.readingType == 'heat').toList()
      ..sort((a, b) {
        final dateCmp = a.readingDate.compareTo(b.readingDate);
        if (dateCmp != 0) return dateCmp;
        final createdCmp = a.createdAt.compareTo(b.createdAt);
        if (createdCmp != 0) return createdCmp;
        final ha = int.tryParse(a.heatNumber) ?? 0;
        final hb = int.tryParse(b.heatNumber) ?? 0;
        return ha.compareTo(hb);
      });

    final result = <String, Map<String, double?>>{};

    void computeDiffs(List<SupabaseReading> sorted) {
      for (int i = 0; i < sorted.length; i++) {
        final cur = sorted[i];
        final curVals = _parseValues(cur.readingValues);
        final diffMap = <String, double?>{};

        if (i == 0) {
          for (final u in widget.matrixUnits) {
            diffMap[u] = null;
          }
        } else {
          final prevVals = _parseValues(sorted[i - 1].readingValues);
          for (final u in widget.matrixUnits) {
            if (curVals.containsKey(u) && prevVals.containsKey(u)) {
              diffMap[u] = ReadingCalculationUtils.calculateDifference(curVals[u]!, prevVals[u]!);
            } else {
              diffMap[u] = null;
            }
          }
        }
        result[cur.id] = diffMap;
      }
    }

    computeDiffs(dayReadings);
    computeDiffs(heatReadings);
    return result;
  }

  static const double _colW = 90.0;
  static const double _fixedW = 80.0;
  static const double _opW = 100.0;
  static const double _checkW = 44.0;

  static void _copyValue(BuildContext context, String text) {
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

  void _copySingleColumn(String colName, List<String> values, {bool chronological = true}) {
    final validVals = values.where((v) => v.isNotEmpty && v != '—').toList();
    if (validVals.isEmpty) return;
    final orderedVals = chronological ? validVals.reversed.toList() : validVals;
    final text = orderedVals.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.table_rows_rounded, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${orderedVals.length} values for "$colName" copied (Heat 1→N for Excel)')),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copySelectedCellsAsColumn({bool chronological = true}) {
    if (_selectedCells.isEmpty) return;
    final sorted = _selectedCells.values.toList()
      ..sort((a, b) {
        // Visual table has newest at top (row 0), oldest at bottom (row max).
        // For chronological Excel order (Heat 1 -> Heat 8 / oldest to newest),
        // we sort row descending (b.row.compareTo(a.row)).
        final rowCmp = chronological ? b.row.compareTo(a.row) : a.row.compareTo(b.row);
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
            const Icon(Icons.table_rows_rounded, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${sorted.length} values copied in ${chronological ? 'Chronological Order (Heat 1→N / for Excel)' : 'Display Order'}')),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copySelectedCellsAsGrid({bool chronological = true}) {
    if (_selectedCells.isEmpty) return;
    final sorted = _selectedCells.values.toList()
      ..sort((a, b) {
        final rowCmp = chronological ? b.row.compareTo(a.row) : a.row.compareTo(b.row);
        if (rowCmp != 0) return rowCmp;
        return a.col.compareTo(b.col);
      });

    final Map<int, List<({int row, int col, String value, String label})>> rowMap = {};
    for (final item in sorted) {
      rowMap.putIfAbsent(item.row, () => []).add(item);
    }

    final StringBuffer buffer = StringBuffer();
    final rowKeys = rowMap.keys.toList();
    if (chronological) {
      rowKeys.sort((a, b) => b.compareTo(a)); // bottom row (Heat 1) first
    } else {
      rowKeys.sort(); // top row (newest) first
    }
    for (final r in rowKeys) {
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
            Expanded(child: Text('${sorted.length} cells copied as Grid in ${chronological ? 'Chronological Order (Heat 1→N / for Excel)' : 'Display Order'}')),
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
    double width = _colW,
    Color? textColor,
    Color? bgColor,
    bool isBold = false,
  }) {
    final isSelected = _selectedCells.containsKey(cellKey);
    final effectiveBg = isSelected
        ? AppColors.primaryContainer.withOpacity(0.65)
        : bgColor;

    return GestureDetector(
      onLongPress: widget.enableExcelCopyTools
          ? () {
              setState(() {
                _cellSelectMode = true;
                _selectedCells[cellKey] = (row: row, col: col, value: text, label: label);
              });
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cell selected for Excel. Tap more cells to add to selection or tap Copy.'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          : null,
      onTap: () {
        if (widget.enableExcelCopyTools) {
          setState(() {
            _cellSelectMode = true;
            if (_selectedCells.containsKey(cellKey)) {
              _selectedCells.remove(cellKey);
            } else {
              _selectedCells[cellKey] = (row: row, col: col, value: text, label: label);
            }
          });
        }
      },
      child: Tooltip(
        message: widget.enableExcelCopyTools
            ? (isSelected ? 'Selected (Tap to deselect)' : 'Tap to select for Excel copy')
            : (text == '—' || text.isEmpty ? '' : text),
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          width: width,
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.withOpacity(0.28) : bgColor,
            border: isSelected ? Border.all(color: Colors.blueAccent, width: 2.0) : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? Colors.blue.shade900 : textColor,
              fontWeight: isSelected || isBold ? FontWeight.bold : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  static Widget _headerCell(
    String text, {
    bool bold = false,
    Color? bg,
    double width = _colW,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final child = Container(
      width: width,
      height: 36,
      alignment: Alignment.center,
      color: bg,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (onTap == null) return child;

    return Tooltip(
      message: tooltip ?? 'Click to copy column for Excel',
      child: InkWell(
        onTap: onTap,
        child: child,
      ),
    );
  }

  static Widget _dividerV() => Container(width: 1, color: Colors.grey.withOpacity(0.2));
  static Widget _dividerH() => Divider(height: 1, color: Colors.grey.withOpacity(0.2));

  void _copySelectedRowsForExcel(List<SupabaseReading> displayReadings, Map<String, Map<String, double?>> diffMap) {
    if (_selectedReadingIds.isEmpty) return;

    final selectedRows = displayReadings.where((r) => _selectedReadingIds.contains(r.id)).toList();
    if (selectedRows.isEmpty) return;

    final StringBuffer buffer = StringBuffer();

    final List<String> headers = [];
    if (widget.showOperatorColumn) headers.add('Operator');
    headers.add('Date');
    headers.add('Reading Time');
    headers.add('Posted Time');
    if (widget.showTypeColumn) {
      headers.add('Type');
      headers.add('Heat #');
    }
    for (final u in widget.matrixUnits) {
      final isCum = _isCumulativeUnit(u);
      final isMf = _isMfUnit(u);
      if (isMf) {
        headers.add('$u Reading');
        headers.add('$u Calc');
      } else if (isCum) {
        headers.add('$u Reading');
        headers.add('$u Diff');
        headers.add('$u Consumption');
      } else {
        headers.add(u);
      }
    }
    buffer.writeln(headers.join('\t'));

    for (final r in selectedRows) {
      final readingDt = DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal();
      final postedDt = DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true).toLocal();
      final dateStr = DateFormat('dd MMM yyyy').format(readingDt);
      final readingTimeStr = DateFormat('hh:mm a').format(readingDt);
      final postedTimeStr = DateFormat('hh:mm a').format(postedDt);
      final values = _parseValues(r.readingValues);
      final isHeat = r.readingType == 'heat';
      final diffs = diffMap[r.id] ?? {};
      final factors = isHeat ? widget.heatUnitFactors : widget.dayUnitFactors;

      final rowCells = <String>[];
      if (widget.showOperatorColumn) {
        rowCells.add(widget.operatorNames[r.id] ?? '');
      }
      rowCells.add(dateStr);
      rowCells.add(readingTimeStr);
      rowCells.add(postedTimeStr);
      if (widget.showTypeColumn) {
        rowCells.add(r.readingType.toUpperCase());
        rowCells.add(r.heatNumber);
      }

      for (final u in widget.matrixUnits) {
        final isCum = _isCumulativeUnit(u);
        final isMf = _isMfUnit(u);
        final rawVal = values[u];
        final valStr = rawVal != null ? rawVal.toStringAsFixed(2) : '';
        final mf = factors[u] ?? 1.0;

        if (isMf) {
          final mdVal = rawVal != null ? rawVal * mf : null;
          rowCells.add(valStr);
          rowCells.add(mdVal != null ? mdVal.toStringAsFixed(2) : '');
        } else if (isCum) {
          final diff = diffs[u];
          final cons = diff != null ? diff * mf : null;
          rowCells.add(valStr);
          rowCells.add(diff != null ? diff.toStringAsFixed(2) : '');
          rowCells.add(cons != null ? cons.toStringAsFixed(2) : '');
        } else {
          rowCells.add(valStr);
        }
      }
      buffer.writeln(rowCells.join('\t'));
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.table_chart_rounded, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('${selectedRows.length} rows copied to clipboard (Tab-separated for Excel paste)')),
          ],
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diffMap = _buildDifferenceMap();

    var displayReadings = List<SupabaseReading>.from(widget.readings);
    if (widget.filterOperatorId != null) {
      displayReadings = displayReadings.where((r) => r.operatorId == widget.filterOperatorId).toList();
    }
    displayReadings.sort((a, b) => b.readingDate.compareTo(a.readingDate));

    final headerBg = theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final unitHeaderBg = AppColors.primaryContainer.withOpacity(0.35);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.enableExcelCopyTools)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: Icon(_cellSelectMode ? Icons.close_rounded : Icons.crop_free_rounded, size: 16),
                  label: Text(
                    _cellSelectMode ? 'Done' : '📋 Select Cells (Excel)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      _cellSelectMode = !_cellSelectMode;
                      if (_cellSelectMode) _selectionMode = false;
                      if (!_cellSelectMode) _selectedCells.clear();
                    });
                  },
                ),
                OutlinedButton.icon(
                  icon: Icon(_selectionMode ? Icons.check_box_outlined : Icons.checklist_rounded, size: 16),
                  label: Text(
                    _selectionMode ? 'Done' : '📋 Select Rows (Full)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectionMode = !_selectionMode;
                      if (_selectionMode) _cellSelectMode = false;
                      if (!_selectionMode) _selectedReadingIds.clear();
                    });
                  },
                ),
                if (_cellSelectMode && _selectedCells.isNotEmpty) ...[
                  Text(
                    '${_selectedCells.length} cells selected',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedCells.clear()),
                    child: const Text('Clear', style: TextStyle(fontSize: 11)),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.table_rows_rounded, size: 14),
                    label: Text('Copy Column (${_selectedCells.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _copySelectedCellsAsColumn,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.grid_on_rounded, size: 14),
                    label: const Text('Copy Grid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _copySelectedCellsAsGrid,
                  ),
                ],
                if (_selectionMode) ...[
                  Text(
                    '${_selectedReadingIds.length} of ${displayReadings.length} rows',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedReadingIds.length == displayReadings.length) {
                          _selectedReadingIds.clear();
                        } else {
                          _selectedReadingIds.addAll(displayReadings.map((r) => r.id));
                        }
                      });
                    },
                    child: Text(
                      _selectedReadingIds.length == displayReadings.length ? 'Deselect All' : 'Select All',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: Text('Copy for Excel (${_selectedReadingIds.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _selectedReadingIds.isEmpty
                        ? null
                        : () => _copySelectedRowsForExcel(displayReadings, diffMap),
                  ),
                ],
              ],
            ),
          ),

        if (widget.enableExcelCopyTools && _selectedCells.isNotEmpty)
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
                      label: Text('Copy for Excel (${_selectedCells.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => _copySelectedCellsAsColumn(chronological: true),
                    ),
                  ],
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
                    Row(children: [
                      if (_selectionMode) Container(width: _checkW, height: 32, color: headerBg),
                      if (widget.showOperatorColumn) Container(width: _opW, height: 32, color: headerBg),
                      Container(width: _fixedW, height: 32, color: headerBg),
                      _dividerV(),
                      Container(width: _fixedW, height: 32, color: headerBg),
                      _dividerV(),
                      Container(width: _fixedW, height: 32, color: headerBg),
                      if (widget.showTypeColumn) ...[
                        _dividerV(),
                        Container(width: _fixedW, height: 32, color: headerBg),
                        _dividerV(),
                        Container(width: _fixedW, height: 32, color: headerBg),
                      ],
                      ...widget.matrixUnits.expand((u) {
                        final isCum = _isCumulativeUnit(u);
                        final isMf = _isMfUnit(u);
                        final width = isCum ? _colW * 3 + 2 : (isMf ? _colW * 2 + 1 : _colW);
                        return [
                          _dividerV(),
                          Container(
                            width: width,
                            height: 32,
                            alignment: Alignment.center,
                            color: unitHeaderBg,
                            child: Text(
                              u,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ),
                        ];
                      }),
                      if (widget.showAdminActions) ...[
                        _dividerV(),
                        Container(width: _fixedW, height: 32, color: headerBg),
                      ],
                    ]),

                    _dividerH(),

                    Row(children: [
                      if (_selectionMode) _headerCell('Select', bold: true, bg: headerBg, width: _checkW),
                      if (widget.showOperatorColumn) _headerCell('Operator', bold: true, bg: headerBg, width: _opW),
                      _headerCell(
                        'Date',
                        bold: true,
                        bg: headerBg,
                        width: _fixedW,
                        onTap: () => _copySingleColumn(
                          'Date',
                          displayReadings.map((r) => DateFormat('dd MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal())).toList(),
                        ),
                        tooltip: 'Click to copy all Dates for Excel',
                      ),
                      _dividerV(),
                      _headerCell(
                        'Reading Time',
                        bold: true,
                        bg: headerBg,
                        width: _fixedW,
                        onTap: () => _copySingleColumn(
                          'Reading Time',
                          displayReadings.map((r) => DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal())).toList(),
                        ),
                        tooltip: 'Click to copy all Reading Times for Excel',
                      ),
                      _dividerV(),
                      _headerCell('Posted Time', bold: true, bg: headerBg, width: _fixedW),
                      if (widget.showTypeColumn) ...[
                        _dividerV(),
                        _headerCell('Type', bold: true, bg: headerBg, width: _fixedW),
                        _dividerV(),
                        _headerCell(
                          'Heat #',
                          bold: true,
                          bg: headerBg,
                          width: _fixedW,
                          onTap: () => _copySingleColumn(
                            'Heat #',
                            displayReadings.map((r) => r.heatNumber).toList(),
                          ),
                          tooltip: 'Click to copy all Heat numbers for Excel',
                        ),
                      ],
                      ...widget.matrixUnits.expand((u) {
                        final isCum = _isCumulativeUnit(u);
                        final isMf = _isMfUnit(u);
                        if (isMf) {
                          return [
                            _dividerV(),
                            _headerCell(
                              'Reading',
                              bg: headerBg,
                              onTap: () => _copySingleColumn(
                                '$u Reading',
                                displayReadings.map((r) => _parseValues(r.readingValues)[u]?.toStringAsFixed(2) ?? '').toList(),
                              ),
                              tooltip: 'Click to copy all $u Reading values for Excel',
                            ),
                            _dividerV(),
                            _headerCell(
                              'Calc (×MF)',
                              bg: headerBg,
                              onTap: () => _copySingleColumn(
                                '$u Calc',
                                displayReadings.map((r) {
                                  final v = _parseValues(r.readingValues)[u];
                                  final mf = (r.readingType == 'heat' ? widget.heatUnitFactors : widget.dayUnitFactors)[u] ?? 1.0;
                                  return v != null ? (v * mf).toStringAsFixed(2) : '';
                                }).toList(),
                              ),
                              tooltip: 'Click to copy all $u Calc values for Excel',
                            ),
                          ];
                        }
                        if (!isCum) {
                          return [
                            _dividerV(),
                            _headerCell(
                              'Reading',
                              bg: headerBg,
                              onTap: () => _copySingleColumn(
                                '$u Reading',
                                displayReadings.map((r) => _parseValues(r.readingValues)[u]?.toStringAsFixed(2) ?? '').toList(),
                              ),
                              tooltip: 'Click to copy all $u Reading values for Excel',
                            ),
                          ];
                        }
                        return [
                          _dividerV(),
                          _headerCell(
                            'Reading',
                            bg: headerBg,
                            onTap: () => _copySingleColumn(
                              '$u Reading',
                              displayReadings.map((r) => _parseValues(r.readingValues)[u]?.toStringAsFixed(2) ?? '').toList(),
                            ),
                            tooltip: 'Click to copy all $u Reading values for Excel',
                          ),
                          _dividerV(),
                          _headerCell(
                            'Difference',
                            bg: headerBg,
                            onTap: () => _copySingleColumn(
                              '$u Difference',
                              displayReadings.map((r) => diffMap[r.id]?[u]?.toStringAsFixed(2) ?? '').toList(),
                            ),
                            tooltip: 'Click to copy all $u Differences for Excel',
                          ),
                          _dividerV(),
                          _headerCell(
                            'Consumption',
                            bg: headerBg,
                            onTap: () => _copySingleColumn(
                              '$u Consumption',
                              displayReadings.map((r) {
                                final diff = diffMap[r.id]?[u];
                                final mf = (r.readingType == 'heat' ? widget.heatUnitFactors : widget.dayUnitFactors)[u] ?? 1.0;
                                return diff != null ? (diff * mf).toStringAsFixed(2) : '';
                              }).toList(),
                            ),
                            tooltip: 'Click to copy all $u Consumptions for Excel',
                          ),
                        ];
                      }),
                      if (widget.showAdminActions) ...[
                        _dividerV(),
                        _headerCell('Actions', bold: true, bg: headerBg, width: _fixedW),
                      ],
                    ]),

                    _dividerH(),

                    ...displayReadings.asMap().entries.map((entry) {
                      final rIdx = entry.key;
                      final r = entry.value;
                      final isSelected = _selectedReadingIds.contains(r.id);
                      final readingDt = DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal();
                      final postedDt = DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true).toLocal();
                      final dateStr = DateFormat('dd MMM yy').format(readingDt);
                      final readingTimeStr = DateFormat('hh:mm a').format(readingDt);
                      final postedTimeStr = DateFormat('hh:mm a').format(postedDt);
                      final values = _parseValues(r.readingValues);
                      final isHeat = r.readingType == 'heat';
                      final diffs = diffMap[r.id] ?? {};
                      final factors = isHeat ? widget.heatUnitFactors : widget.dayUnitFactors;

                      final kwhDiff = diffs['KWH'] ?? diffs['kwh'];
                      final kvahDiff = diffs['KVAH'] ?? diffs['kvah'];
                      final kwhMf = factors['KWH'] ?? factors['kwh'] ?? 1.0;
                      final kvahMf = factors['KVAH'] ?? factors['kvah'] ?? 1.0;
                      final kwhCons = kwhDiff != null ? kwhDiff * kwhMf : null;
                      final kvahCons = kvahDiff != null ? kvahDiff * kvahMf : null;
                      final calculatedPf = (kwhCons != null && kvahCons != null && kvahCons > 0)
                          ? (kwhCons / kvahCons)
                          : null;

                      final rowBg = isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.3) : null;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            if (_selectionMode)
                              Container(
                                width: _checkW,
                                height: 40,
                                alignment: Alignment.center,
                                color: rowBg,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedReadingIds.add(r.id);
                                      } else {
                                        _selectedReadingIds.remove(r.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                            if (widget.showOperatorColumn)
                              _buildInteractiveCell(
                                cellKey: 'op_$rIdx',
                                row: rIdx,
                                col: 0,
                                text: widget.operatorNames[r.id] ?? '—',
                                label: 'Operator',
                                width: _opW,
                                bgColor: rowBg,
                              ),
                            _buildInteractiveCell(
                              cellKey: 'date_$rIdx',
                              row: rIdx,
                              col: 1,
                              text: dateStr,
                              label: 'Date',
                              width: _fixedW,
                              bgColor: rowBg,
                            ),
                            _dividerV(),
                            _buildInteractiveCell(
                              cellKey: 'rtime_$rIdx',
                              row: rIdx,
                              col: 2,
                              text: readingTimeStr,
                              label: 'Reading Time',
                              width: _fixedW,
                              bgColor: rowBg,
                            ),
                            _dividerV(),
                            _buildInteractiveCell(
                              cellKey: 'ptime_$rIdx',
                              row: rIdx,
                              col: 3,
                              text: postedTimeStr,
                              label: 'Posted Time',
                              width: _fixedW,
                              bgColor: rowBg,
                            ),
                            if (widget.showTypeColumn) ...[
                              _dividerV(),
                              Container(
                                width: _fixedW,
                                height: 40,
                                alignment: Alignment.center,
                                color: rowBg,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isHeat ? AppColors.heatColorBg : AppColors.dayColorBg,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    r.readingType.toUpperCase(),
                                    style: TextStyle(
                                      color: isHeat ? AppColors.heatColor : AppColors.dayColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                              _dividerV(),
                              _buildInteractiveCell(
                                cellKey: 'heat_$rIdx',
                                row: rIdx,
                                col: 4,
                                text: r.heatNumber.isEmpty ? '—' : r.heatNumber,
                                label: 'Heat #',
                                width: _fixedW,
                                bgColor: rowBg,
                              ),
                            ],
                            ...widget.matrixUnits.asMap().entries.expand((uEntry) {
                              final uIdx = uEntry.key;
                              final u = uEntry.value;
                              final isCum = _isCumulativeUnit(u);
                              final uUpper = u.toUpperCase();
                              final rawVal = values[u];

                              final displayReading = (uUpper == 'PF' && calculatedPf != null)
                                  ? calculatedPf.toStringAsFixed(2)
                                  : (values.containsKey(u) ? values[u]!.toStringAsFixed(2) : '—');

                              final diff = diffs[u];
                              final mf = factors[u] ?? 1.0;
                              final consumption = diff != null ? diff * mf : null;

                              final diffStr = diff != null ? diff.toStringAsFixed(2) : '—';
                              final consStr = consumption != null
                                  ? NumberFormat('#,##0.##').format(consumption)
                                  : '—';

                              Color? cellTextColor;
                              Color? cellBgColor = rowBg;
                              bool cellBold = false;

                              final currentPfVal = (uUpper == 'PF' && calculatedPf != null)
                                  ? calculatedPf
                                  : rawVal;

                              if (uUpper == 'PF' && currentPfVal != null && currentPfVal > 1.0) {
                                cellTextColor = Colors.red.shade900;
                                cellBgColor = Colors.red.shade100;
                                cellBold = true;
                              }

                              if (calculatedPf != null && calculatedPf > 1.0) {
                                if (uUpper == 'PF' || uUpper == 'KWH' || uUpper == 'KVAH') {
                                  cellTextColor = Colors.red.shade900;
                                  cellBgColor = Colors.red.shade100;
                                  cellBold = true;
                                }
                              }

                              final isMf = _isMfUnit(u);
                              final colBase = 5 + uIdx * 3;

                              if (isMf) {
                                final mdVal = rawVal != null ? rawVal * mf : null;
                                final mdValStr = mdVal != null ? NumberFormat('#,##0.##').format(mdVal) : '—';
                                return [
                                  _dividerV(),
                                  _buildInteractiveCell(
                                    cellKey: 'u_rdg_${rIdx}_$uIdx',
                                    row: rIdx,
                                    col: colBase,
                                    text: displayReading,
                                    label: '$u Reading',
                                    textColor: cellTextColor,
                                    bgColor: cellBgColor,
                                    isBold: cellBold,
                                  ),
                                  _dividerV(),
                                  _buildInteractiveCell(
                                    cellKey: 'u_calc_${rIdx}_$uIdx',
                                    row: rIdx,
                                    col: colBase + 1,
                                    text: mdValStr,
                                    label: '$u Calc',
                                    textColor: cellTextColor,
                                    bgColor: cellBgColor,
                                    isBold: cellBold,
                                  ),
                                ];
                              }

                              if (!isCum) {
                                return [
                                  _dividerV(),
                                  _buildInteractiveCell(
                                    cellKey: 'u_rdg_${rIdx}_$uIdx',
                                    row: rIdx,
                                    col: colBase,
                                    text: displayReading,
                                    label: '$u Reading',
                                    textColor: cellTextColor,
                                    bgColor: cellBgColor,
                                    isBold: cellBold,
                                  ),
                                ];
                              }

                              final diffColor = cellTextColor ?? (diff == null
                                  ? null
                                  : diff >= 0
                                      ? AppColors.success
                                      : AppColors.error);

                              return [
                                _dividerV(),
                                _buildInteractiveCell(
                                  cellKey: 'u_rdg_${rIdx}_$uIdx',
                                  row: rIdx,
                                  col: colBase,
                                  text: displayReading,
                                  label: '$u Reading',
                                  textColor: cellTextColor,
                                  bgColor: cellBgColor,
                                  isBold: cellBold,
                                ),
                                _dividerV(),
                                _buildInteractiveCell(
                                  cellKey: 'u_diff_${rIdx}_$uIdx',
                                  row: rIdx,
                                  col: colBase + 1,
                                  text: diffStr,
                                  label: '$u Diff',
                                  textColor: diffColor,
                                  bgColor: cellBgColor,
                                  isBold: cellBold,
                                ),
                                _dividerV(),
                                _buildInteractiveCell(
                                  cellKey: 'u_cons_${rIdx}_$uIdx',
                                  row: rIdx,
                                  col: colBase + 2,
                                  text: consStr,
                                  label: '$u Consumption',
                                  textColor: cellTextColor,
                                  bgColor: cellBgColor,
                                  isBold: cellBold,
                                ),
                              ];
                            }),
                            if (widget.showAdminActions) ...[
                              _dividerV(),
                              SizedBox(
                                width: _fixedW,
                                height: 40,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () async {
                                          await context.push(RoutePaths.adminReadingEditPath(r.id), extra: r);
                                          ref.invalidate(adminReadingsProvider);
                                          ref.invalidate(adminHeatSummaryReadingsProvider);
                                          ref.invalidate(adminDaySummaryReadingsProvider);
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                          child: Icon(Icons.edit_rounded, size: 16, color: Colors.blueGrey),
                                        ),
                                      ),
                                    ),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => _deleteReading(context, ref, r.id),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                          child: Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ]),
                          _dividerH(),
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

  Future<void> _deleteReading(BuildContext context, WidgetRef ref, String readingId) async {
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
      try {
        await ref.read(supabaseReadingsRepoProvider).delete(readingId);
        ref.invalidate(adminReadingsProvider);
        ref.invalidate(adminDaySummaryReadingsProvider);
        ref.invalidate(adminHeatSummaryReadingsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reading deleted successfully'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete reading: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }
}

/// Helper to parse a JSON factor map string to Map<String, double>.
Map<String, double> parseFactorMap(String json) {
  try {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
  } catch (_) {
    return {};
  }
}
