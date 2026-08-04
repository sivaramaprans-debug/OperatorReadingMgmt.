import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';
import '../../../../database/supabase_providers.dart';
import '../../../../routing/route_paths.dart';
import '../notifiers/admin_readings_notifier.dart';

/// A horizontally-scrollable table with two header rows per unit:
///   Row 1 — unit name spanning 3 sub-columns
///   Row 2 — Reading | Difference | Consumption
///
/// Difference rules:
///   Day:  current reading  − previous day reading  (sorted by readingDate asc)
///   Heat: current heat     − previous heat reading (sorted by heatNumber asc as int)
///
/// Consumption = Difference × per-unit MF (from [heatUnitFactors] / [dayUnitFactors]).
class ReadingsCalculatedTable extends ConsumerWidget {
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
  });

  final List<SupabaseReading> readings;
  final List<String> matrixUnits;
  final bool showTypeColumn;
  final Map<String, double> heatUnitFactors;
  final Map<String, double> dayUnitFactors;
  /// Pass true in admin view to show an Operator column.
  final bool showOperatorColumn;
  /// Map from readingId → operatorName (used when showOperatorColumn is true).
  final Map<String, String> operatorNames;
  /// Pass true to show Edit/Delete buttons
  final bool showAdminActions;

  static bool _isCumulativeUnit(String unit) {
    final u = unit.trim().toUpperCase();
    return u == 'KWH' || u == 'KWHLT' || u == 'KVAH' || u == 'KVARH';
  }

  static bool _isMfUnit(String unit) {
    final u = unit.trim().toUpperCase();
    return u == 'MD';
  }

  // ── Calculation helpers ────────────────────────────────────────────────

  /// Parse JSON values map from a reading.
  static Map<String, double> _parseValues(String json) {
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  /// Build a lookup: readingId → {unit: difference}
  Map<String, Map<String, double?>> _buildDifferenceMap() {
    // Separate Day and Heat/Standard readings.
    final dayReadings = readings
        .where((r) => r.readingType == 'day' || r.readingType == 'standard')
        .toList()
      ..sort((a, b) => a.readingDate.compareTo(b.readingDate)); // asc by date

    final heatReadings = readings.where((r) => r.readingType == 'heat').toList()
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
          // First reading — no previous.
          for (final u in matrixUnits) {
            diffMap[u] = null;
          }
        } else {
          final prevVals = _parseValues(sorted[i - 1].readingValues);
          for (final u in matrixUnits) {
            if (curVals.containsKey(u) && prevVals.containsKey(u)) {
              diffMap[u] = curVals[u]! - prevVals[u]!;
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

  // ── Cell / header helpers ─────────────────────────────────────────────

  static const double _colW = 90.0;   // reading/diff/consumption column width
  static const double _fixedW = 80.0; // Date, Time, Type, Heat# columns
  static const double _opW = 100.0;   // Operator column

  static Widget _headerCell(String text, {bool bold = false, Color? bg, double width = _colW}) =>
      Container(
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

  static Widget _dataCell(
    String text, {
    double width = _colW,
    Color? textColor,
    Color? bgColor,
    bool isBold = false,
  }) =>
      Container(
        width: width,
        height: 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        color: bgColor,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: textColor,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

  static Widget _dividerV() => Container(width: 1, color: Colors.grey.withOpacity(0.2));
  static Widget _dividerH() => Divider(height: 1, color: Colors.grey.withOpacity(0.2));

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final diffMap = _buildDifferenceMap();

    // Display order: newest first
    final displayReadings = List<SupabaseReading>.from(readings)
      ..sort((a, b) => b.readingDate.compareTo(a.readingDate));

    final headerBg = theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final unitHeaderBg = AppColors.primaryContainer.withOpacity(0.35);

    return Builder(
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
          // ── Header Row 1: unit spanning headers ──────────────────────
          Row(children: [
            // Fixed left placeholder
            if (showOperatorColumn) Container(width: _opW, height: 32, color: headerBg),
            Container(width: _fixedW, height: 32, color: headerBg), // Date
            _dividerV(),
            Container(width: _fixedW, height: 32, color: headerBg), // Reading Time
            _dividerV(),
            Container(width: _fixedW, height: 32, color: headerBg), // Posted Time
            if (showTypeColumn) ...[
              _dividerV(),
              Container(width: _fixedW, height: 32, color: headerBg), // Type
              _dividerV(),
              Container(width: _fixedW, height: 32, color: headerBg), // Heat#
            ],
            // Unit spanning headers
            ...matrixUnits.expand((u) {
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
            if (showAdminActions) ...[
              _dividerV(),
              Container(width: _fixedW, height: 32, color: headerBg), // Actions placeholder
            ],
          ]),

          _dividerH(),

          // ── Header Row 2: sub-column headers ────────────────────────
          Row(children: [
            if (showOperatorColumn) _headerCell('Operator', bold: true, bg: headerBg, width: _opW),
            _headerCell('Date', bold: true, bg: headerBg, width: _fixedW),
            _dividerV(),
            _headerCell('Reading Time', bold: true, bg: headerBg, width: _fixedW),
            _dividerV(),
            _headerCell('Posted Time', bold: true, bg: headerBg, width: _fixedW),
            if (showTypeColumn) ...[
              _dividerV(),
              _headerCell('Type', bold: true, bg: headerBg, width: _fixedW),
              _dividerV(),
              _headerCell('Heat #', bold: true, bg: headerBg, width: _fixedW),
            ],
            ...matrixUnits.expand((u) {
              final isCum = _isCumulativeUnit(u);
              final isMf = _isMfUnit(u);
              if (isCum) {
                return [
                  _dividerV(),
                  _headerCell('Reading', bg: unitHeaderBg.withOpacity(0.5)),
                  _dividerV(),
                  _headerCell('Difference', bg: unitHeaderBg.withOpacity(0.5)),
                  _dividerV(),
                  _headerCell('Consumption', bg: unitHeaderBg.withOpacity(0.5)),
                ];
              } else if (isMf) {
                return [
                  _dividerV(),
                  _headerCell('Reading', bg: unitHeaderBg.withOpacity(0.5)),
                  _dividerV(),
                  _headerCell('MD Value', bg: unitHeaderBg.withOpacity(0.5)),
                ];
              } else {
                return [
                  _dividerV(),
                  _headerCell('Value', bg: unitHeaderBg.withOpacity(0.5)),
                ];
              }
            }),
            if (showAdminActions) ...[
              _dividerV(),
              _headerCell('Actions', bold: true, bg: headerBg, width: _fixedW),
            ],
          ]),

          _dividerH(),

          // ── Data rows ─────────────────────────────────────────────────
          ...displayReadings.map((r) {
            final readingDt = DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal();
            final postedDt = DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true).toLocal();
            final dateStr = DateFormat('dd MMM yy').format(readingDt);
            final readingTimeStr = DateFormat('hh:mm a').format(readingDt);
            final postedTimeStr = DateFormat('hh:mm a').format(postedDt);
            final values = _parseValues(r.readingValues);
            final isHeat = r.readingType == 'heat';
            final diffs = diffMap[r.id] ?? {};
            final factors = isHeat ? heatUnitFactors : dayUnitFactors;

            // Calculate PF = (KWH Consumption / KVAH Consumption) for this reading row
            final kwhDiff = diffs['KWH'] ?? diffs['kwh'];
            final kvahDiff = diffs['KVAH'] ?? diffs['kvah'];
            final kwhMf = factors['KWH'] ?? factors['kwh'] ?? 1.0;
            final kvahMf = factors['KVAH'] ?? factors['kvah'] ?? 1.0;
            final kwhCons = kwhDiff != null ? kwhDiff * kwhMf : null;
            final kvahCons = kvahDiff != null ? kvahDiff * kvahMf : null;
            final calculatedPf = (kwhCons != null && kvahCons != null && kvahCons > 0)
                ? (kwhCons / kvahCons)
                : null;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  if (showOperatorColumn)
                    _dataCell(operatorNames[r.id] ?? '—', width: _opW),
                  _dataCell(dateStr, width: _fixedW),
                  _dividerV(),
                  _dataCell(readingTimeStr, width: _fixedW),
                  _dividerV(),
                  _dataCell(postedTimeStr, width: _fixedW),
                  if (showTypeColumn) ...[
                    _dividerV(),
                    // Type chip
                    Container(
                      width: _fixedW,
                      height: 40,
                      alignment: Alignment.center,
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
                    _dataCell(r.heatNumber.isEmpty ? '—' : r.heatNumber, width: _fixedW),
                  ],
                  ...matrixUnits.expand((u) {
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
                    Color? cellBgColor;
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
                    if (isMf) {
                      final mdVal = rawVal != null ? rawVal * mf : null;
                      final mdValStr = mdVal != null ? NumberFormat('#,##0.##').format(mdVal) : '—';
                      return [
                        _dividerV(),
                        _dataCell(displayReading, textColor: cellTextColor, bgColor: cellBgColor, isBold: cellBold),
                        _dividerV(),
                        _dataCell(mdValStr, textColor: cellTextColor, bgColor: cellBgColor, isBold: cellBold),
                      ];
                    }

                    if (!isCum) {
                      return [
                        _dividerV(),
                        _dataCell(displayReading, textColor: cellTextColor, bgColor: cellBgColor, isBold: cellBold),
                      ];
                    }

                    final diffColor = cellTextColor ?? (diff == null
                        ? null
                        : diff >= 0
                            ? AppColors.success
                            : AppColors.error);

                    return [
                      _dividerV(),
                      _dataCell(displayReading, textColor: cellTextColor, bgColor: cellBgColor, isBold: cellBold),
                      _dividerV(),
                      _dataCell(diffStr, textColor: diffColor, bgColor: cellBgColor, isBold: cellBold),
                      _dividerV(),
                      _dataCell(consStr, textColor: cellTextColor, bgColor: cellBgColor, isBold: cellBold),
                    ];
                  }),
                  if (showAdminActions) ...[
                    _dividerV(),
                    SizedBox(
                      width: _fixedW,
                      height: 40,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 16),
                            onPressed: () {
                              context.push(RoutePaths.adminReadingEditPath(r.id), extra: r);
                            },
                            tooltip: 'Edit',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                            onPressed: () async {
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
                                await ref.read(supabaseReadingsRepoProvider).delete(r.id);
                                ref.invalidate(adminReadingsProvider);
                              }
                            },
                            tooltip: 'Delete',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
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
  );
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
