import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/utils/app_date_utils.dart';
import '../../../../core/utils/reading_calculation_utils.dart';
import '../../../../database/repositories/supabase_devices_repository.dart';
import '../../../../database/repositories/supabase_meter_replacement_repository.dart';
import '../../../../database/repositories/supabase_operators_repository.dart';
import '../../../../database/repositories/supabase_readings_repository.dart';

class ExportReadingsUseCase {
  
  Map<String, double> _parseValues(String json) {
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Map<String, double> _parseFactors(String json) {
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }
  
  Future<String?> _saveFile(List<int> bytes, String fileName) async {
    try {
      if (kIsWeb) {
        return null;
      }
      Directory? dir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          dir = downloadDir;
        } else {
          try {
            dir = await getExternalStorageDirectory();
          } catch (_) {}
        }
      } else {
        try {
          dir = await getDownloadsDirectory();
        } catch (_) {}
      }
      try {
        dir ??= await getApplicationDocumentsDirectory();
      } catch (_) {}
      dir ??= Directory.systemTemp;
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      debugPrint('Save file error: $e');
      return null;
    }
  }

  /// Exports Admin Sheet (matrix format) to Excel for filtered data
  Future<String?> exportAdminSheetToExcel({
    required String sheetTitle,
    required List<dynamic> devices,
    required List<SupabaseReadingWithDetails> readings,
    required Map<String, Map<String, double?>> diffMap,
    required Map<String, Map<String, double>> deviceFactors,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheetName = sheetTitle.replaceAll(RegExp(r'[\\/?*\[\]]'), '_');
      final sheet = excel[sheetName];
      excel.delete('Sheet1');

      final isHeat = sheetTitle.contains('Heat');

      final row1 = <CellValue?>[
        TextCellValue('Date'),
      ];

      final row2 = <CellValue?>[
        TextCellValue(''),
      ];

      for (final d in devices) {
        row1.add(TextCellValue(d.name as String));
        if (isHeat) {
          row1.add(TextCellValue(''));
          row1.add(TextCellValue(''));
          row1.add(TextCellValue(''));
          row2.add(TextCellValue('Heat #'));
          row2.add(TextCellValue('Time'));
        } else {
          row1.add(TextCellValue(''));
        }
        row2.add(TextCellValue('KWH Consump'));
        row2.add(TextCellValue('KWHLT Consump'));
      }

      sheet.appendRow(row1);
      sheet.appendRow(row2);

      if (isHeat) {
        // Grouping logic for Heat
        final Map<String, List<SupabaseReadingWithDetails>> deviceReadingsMap = {};
        for (final rwd in readings) {
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

        final List<_GroupedHeatRow> groupedHeatRows = [];
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

        for (final gr in groupedHeatRows) {
          final dateStr = DateFormat('dd MMM yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(gr.businessDayMidnightMs, isUtc: true).toLocal(),
          );

          final row = <CellValue?>[
            TextCellValue(dateStr),
          ];

          for (final d in devices) {
            final rwd = gr.deviceReadings[d.id as String];
            if (rwd == null) {
              row.add(TextCellValue('-'));
              row.add(TextCellValue('-'));
              row.add(TextCellValue('-'));
              row.add(TextCellValue('-'));
            } else {
              final r = rwd.reading;
              final readingTimeStr = DateFormat('hh:mm a').format(
                DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal(),
              );

              final diffs = diffMap[r.id] ?? {};
              final kwhDiff = diffs['KWH'] ?? diffs['kwh'];
              final kwhltDiff = diffs['KWHLT'] ?? diffs['kwhlt'];

              final factors = deviceFactors[d.id as String] ?? {};
              final kwhFactor = factors['KWH'] ?? factors['kwh'] ?? 1.0;
              final kwhltFactor = factors['KWHLT'] ?? factors['kwhlt'] ?? 1.0;

              final kwhCons = kwhDiff != null ? kwhDiff * kwhFactor : null;
              final kwhltCons = kwhltDiff != null ? kwhltDiff * kwhltFactor : null;

              row.add(TextCellValue(r.heatNumber));
              row.add(TextCellValue(readingTimeStr));
              row.add(kwhCons != null ? DoubleCellValue(kwhCons) : TextCellValue('-'));
              row.add(kwhltCons != null ? DoubleCellValue(kwhltCons) : TextCellValue('-'));
            }
          }
          sheet.appendRow(row);
        }
      } else {
        // Grouping logic for Day Summary (exactly one row per Business Day)
        final Map<int, Map<String, SupabaseReadingWithDetails>> groupedDayRows = {};
        for (final rwd in readings) {
          final bizDay = AppDateUtils.toBusinessDayMidnightUtcMs(rwd.reading.readingDate);
          groupedDayRows.putIfAbsent(bizDay, () => {})[rwd.reading.deviceId] = rwd;
        }

        final sortedDayKeys = groupedDayRows.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        for (final day in sortedDayKeys) {
          final dateStr = DateFormat('dd MMM yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(day, isUtc: true).toLocal(),
          );

          final row = <CellValue?>[
            TextCellValue(dateStr),
          ];

          for (final d in devices) {
            final rwd = groupedDayRows[day]?[d.id as String];
            if (rwd == null) {
              row.add(TextCellValue('-'));
              row.add(TextCellValue('-'));
            } else {
              final r = rwd.reading;
              final diffs = diffMap[r.id] ?? {};
              final kwhDiff = diffs['KWH'] ?? diffs['kwh'];
              final kwhltDiff = diffs['KWHLT'] ?? diffs['kwhlt'];

              final factors = deviceFactors[d.id as String] ?? {};
              final kwhFactor = factors['KWH'] ?? factors['kwh'] ?? 1.0;
              final kwhltFactor = factors['KWHLT'] ?? factors['kwhlt'] ?? 1.0;

              final kwhCons = kwhDiff != null ? kwhDiff * kwhFactor : null;
              final kwhltCons = kwhltDiff != null ? kwhltDiff * kwhltFactor : null;

              row.add(kwhCons != null ? DoubleCellValue(kwhCons) : TextCellValue('-'));
              row.add(kwhltCons != null ? DoubleCellValue(kwhltCons) : TextCellValue('-'));
            }
          }
          sheet.appendRow(row);
        }
      }

      final bytes = excel.save();
      if (bytes == null) return null;

      final fileName = '${sheetName}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      return await _saveFile(bytes, fileName);
    } catch (e) {
      debugPrint('Export Admin Sheet Excel error: $e');
      return null;
    }
  }

  /// Exports readings to Excel and saves to Downloads
  Future<bool> exportToExcel(List<SupabaseReadingWithDetails> readings) async {
    try {
      final excel = Excel.createExcel();
      excel.delete('Sheet1');

      final grouped = <String, List<SupabaseReadingWithDetails>>{};
      for (final r in readings) {
        grouped.putIfAbsent(r.deviceName, () => []).add(r);
      }

      for (final entry in grouped.entries) {
        final deviceName = entry.key;
        final deviceReadings = entry.value;
        final sheetName = deviceName.replaceAll(RegExp(r'[\\/?*\[\]]'), '_').substring(0, deviceName.length > 31 ? 31 : deviceName.length);
        final sheet = excel[sheetName];

        final first = deviceReadings.first;
        final heatUnits = first.deviceMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final dayUnits = first.deviceDayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final allUnits = {...heatUnits, ...dayUnits}.toList();
        
        final headers = <CellValue?>[
          TextCellValue('Date'),
          TextCellValue('Time'),
          TextCellValue('Operator'),
          TextCellValue('Type'),
          TextCellValue('Heat #'),
        ];
        
        for (final u in allUnits) {
          headers.add(TextCellValue('$u Reading'));
          headers.add(TextCellValue('$u Diff'));
          headers.add(TextCellValue('$u Consump'));
        }
        
        sheet.appendRow(headers);

        final daySorted = deviceReadings
            .where((r) => r.reading.readingType == 'day' || r.reading.readingType == 'standard')
            .toList()
          ..sort((a, b) => a.reading.readingDate.compareTo(b.reading.readingDate));

        final heatSorted = deviceReadings
            .where((r) => r.reading.readingType == 'heat')
            .toList()
          ..sort((a, b) => a.reading.readingDate.compareTo(b.reading.readingDate));

        final todSorted = deviceReadings
            .where((r) {
              if (r.reading.readingType != 'tod') return false;
              final h = r.reading.heatNumber.toLowerCase();
              final dt = DateTime.fromMillisecondsSinceEpoch(r.reading.readingDate, isUtc: true).toLocal();
              return !h.contains('12') && dt.hour != 12;
            })
            .toList()
          ..sort((a, b) => a.reading.readingDate.compareTo(b.reading.readingDate));

        final diffMap = <String, Map<String, double?>>{};
        void calcGroupDiff(List<SupabaseReadingWithDetails> group) {
          for (int i = 0; i < group.length; i++) {
            final cur = group[i];
            final prev = i > 0 ? group[i - 1] : null;
            final curVals = _parseValues(cur.reading.readingValues);
            final prevVals = prev != null ? _parseValues(prev.reading.readingValues) : <String, double>{};

            final map = <String, double?>{};
            for (final u in allUnits) {
              if (curVals.containsKey(u)) {
                if (prevVals.containsKey(u)) {
                  map[u] = ReadingCalculationUtils.calculateDifference(curVals[u]!, prevVals[u]!);
                } else {
                  map[u] = null;
                }
              }
            }
            diffMap[cur.reading.id] = map;
          }
        }

        calcGroupDiff(daySorted);
        calcGroupDiff(heatSorted);
        calcGroupDiff(todSorted);

        for (final rwd in deviceReadings) {
          final r = rwd.reading;
          final dt = DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true).toLocal();
          final dateStr = DateFormat('dd MMM yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal(),
          );
          final timeStr = DateFormat('HH:mm').format(dt);
          final isHeat = r.readingType == 'heat';
          
          final heatFactors = _parseFactors(rwd.deviceHeatUnitFactors);
          final dayFactors = _parseFactors(rwd.deviceDayUnitFactors);
          final factors = isHeat ? heatFactors : dayFactors;
          
          final vals = _parseValues(r.readingValues);
          final diffs = diffMap[r.id] ?? {};

          final row = <CellValue?>[
            TextCellValue(dateStr),
            TextCellValue(timeStr),
            TextCellValue(rwd.operatorName),
            TextCellValue(r.readingType),
            TextCellValue(r.heatNumber.isEmpty ? '-' : r.heatNumber),
          ];

          for (final u in allUnits) {
            final val = vals[u];
            final diff = diffs[u];
            final mf = factors[u] ?? 1.0;
            final cons = diff != null ? diff * mf : null;

            row.add(val != null ? DoubleCellValue(val) : TextCellValue('-'));
            row.add(diff != null ? DoubleCellValue(diff) : TextCellValue('-'));
            row.add(cons != null ? DoubleCellValue(cons) : TextCellValue('-'));
          }

          sheet.appendRow(row);
        }
      }

      final bytes = excel.save();
      if (bytes == null) return false;

      final fileName = 'Readings_Export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      return (await _saveFile(bytes, fileName)) != null;
    } catch (e) {
      debugPrint('Export Excel error: $e');
      return false;
    }
  }

  /// Exports readings to PDF and saves to Downloads
  Future<bool> exportToPdf(List<SupabaseReadingWithDetails> readings) async {
    try {
      final pdf = pw.Document();

      final grouped = <String, List<SupabaseReadingWithDetails>>{};
      for (final r in readings) {
        grouped.putIfAbsent(r.deviceName, () => []).add(r);
      }

      for (final entry in grouped.entries) {
        final deviceName = entry.key;
        final deviceReadings = entry.value;

        final first = deviceReadings.first;
        final heatUnits = first.deviceMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final dayUnits = first.deviceDayMatrix.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final allUnits = {...heatUnits, ...dayUnits}.toList();

        final daySorted = deviceReadings
            .where((r) => r.reading.readingType == 'day' || r.reading.readingType == 'standard')
            .toList()
          ..sort((a, b) => a.reading.readingDate.compareTo(b.reading.readingDate));

        final heatSorted = deviceReadings
            .where((r) => r.reading.readingType == 'heat')
            .toList()
          ..sort((a, b) => a.reading.readingDate.compareTo(b.reading.readingDate));

        final todSorted = deviceReadings
            .where((r) {
              if (r.reading.readingType != 'tod') return false;
              final h = r.reading.heatNumber.toLowerCase();
              final dt = DateTime.fromMillisecondsSinceEpoch(r.reading.readingDate, isUtc: true).toLocal();
              return !h.contains('12') && dt.hour != 12;
            })
            .toList()
          ..sort((a, b) => a.reading.readingDate.compareTo(b.reading.readingDate));

        final diffMap = <String, Map<String, double?>>{};
        void calcGroupDiff(List<SupabaseReadingWithDetails> group) {
          for (int i = 0; i < group.length; i++) {
            final cur = group[i];
            final prev = i > 0 ? group[i - 1] : null;
            final curVals = _parseValues(cur.reading.readingValues);
            final prevVals = prev != null ? _parseValues(prev.reading.readingValues) : <String, double>{};

            final map = <String, double?>{};
            for (final u in allUnits) {
              if (curVals.containsKey(u)) {
                if (prevVals.containsKey(u)) {
                  map[u] = ReadingCalculationUtils.calculateDifference(curVals[u]!, prevVals[u]!);
                } else {
                  map[u] = null;
                }
              }
            }
            diffMap[cur.reading.id] = map;
          }
        }

        calcGroupDiff(daySorted);
        calcGroupDiff(heatSorted);
        calcGroupDiff(todSorted);

        final headers = [
          'Date', 'Time', 'Op', 'Type', 'Heat',
          ...allUnits.expand((u) => ['$u R', '$u D', '$u C'])
        ];

        final data = <List<String>>[];
        for (final rwd in deviceReadings) {
          final r = rwd.reading;
          final dt = DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true).toLocal();
          final dateStr = DateFormat('dd/MM').format(
            DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal(),
          );
          final timeStr = DateFormat('HH:mm').format(dt);
          final isHeat = r.readingType == 'heat';
          
          final heatFactors = _parseFactors(rwd.deviceHeatUnitFactors);
          final dayFactors = _parseFactors(rwd.deviceDayUnitFactors);
          final factors = isHeat ? heatFactors : dayFactors;
          
          final vals = _parseValues(r.readingValues);
          final diffs = diffMap[r.id] ?? {};

          final row = [
            dateStr,
            timeStr,
            rwd.operatorName.length > 5 ? rwd.operatorName.substring(0, 5) : rwd.operatorName,
            r.readingType == 'heat' ? 'H' : 'D',
            r.heatNumber.isEmpty ? '-' : r.heatNumber,
          ];

          for (final u in allUnits) {
            final val = vals[u];
            final diff = diffs[u];
            final mf = factors[u] ?? 1.0;
            final cons = diff != null ? diff * mf : null;

            row.add(val != null ? val.toStringAsFixed(1) : '-');
            row.add(diff != null ? diff.toStringAsFixed(1) : '-');
            row.add(cons != null ? cons.toStringAsFixed(1) : '-');
          }
          data.add(row);
        }

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(24),
            build: (context) => [
              pw.Text('Device: $deviceName', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.center,
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              ),
            ],
          ),
        );
      }

      final bytes = await pdf.save();
      final fileName = 'Readings_Export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
      return (await _saveFile(bytes, fileName)) != null;
    } catch (e) {
      debugPrint('Export PDF error: $e');
      return false;
    }
  }

  /// Exports a comprehensive 4-sheet monthly report for the billing cycle
  /// (1st of [month] to 1st of next month) to Excel.
  Future<String?> generateAndExportMonthlyReport({
    required int year,
    required int month, // 1..12
    required SupabaseDevicesRepository devicesRepo,
    required SupabaseOperatorsRepository operatorsRepo,
    required SupabaseReadingsRepository readingsRepo,
    required SupabaseMeterReplacementRepository replacementsRepo,
  }) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);
    // Buffer query start by 2 days so predecessor reading on 31st or 1st is always present
    final fromDateMs = AppDateUtils.toLocalMidnightUtcMs(startDate.subtract(const Duration(days: 2)));
    // Include entire day of the 1st of next month
    final toDateMs = AppDateUtils.toLocalMidnightUtcMs(endDate) + 86399999;


    final results = await Future.wait([
      devicesRepo.getAll(),
      operatorsRepo.getAll(),
      devicesRepo.getAllActiveAssignments(),
      replacementsRepo.getAll(),
      readingsRepo.search(
        readingType: 'day',
        fromDateMs: fromDateMs,
        toDateMs: toDateMs,
        limit: 10000,
      ),
    ]);

    final devices = results[0] as List<SupabaseDevice>;
    final operators = results[1] as List<SupabaseOperator>;
    final activeAssignments = results[2] as List<Map<String, dynamic>>;
    final replacements = results[3] as List<SupabaseMeterReplacement>;
    final readings = results[4] as List<SupabaseReadingWithDetails>;

    return exportMonthlyReportToExcel(
      year: year,
      month: month,
      devices: devices,
      operators: operators,
      activeAssignments: activeAssignments,
      readings: readings,
      replacements: replacements,
    );
  }

  /// Generates the 4-sheet Excel workbook from pre-fetched data.
  Future<String?> exportMonthlyReportToExcel({
    required int year,
    required int month,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required List<Map<String, dynamic>> activeAssignments,
    required List<SupabaseReadingWithDetails> readings,
    required List<SupabaseMeterReplacement> replacements,
  }) async {
    try {
      final excel = Excel.createExcel();

      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 1);
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final List<DateTime> cycleDates = [];
      for (int d = 1; d <= daysInMonth; d++) {
        cycleDates.add(DateTime(year, month, d));
      }
      cycleDates.add(DateTime(year, month + 1, 1)); // 1st of next month

      // Index readings by device and date
      final Map<String, Map<DateTime, SupabaseReadingWithDetails>> deviceDayReadings = {};
      for (final rwd in readings) {
        if (rwd.reading.readingType != 'day') continue;
        final dt = DateTime.fromMillisecondsSinceEpoch(rwd.reading.readingDate, isUtc: true).toLocal();
        final dayKey = DateTime(dt.year, dt.month, dt.day);
        final existing = deviceDayReadings[rwd.reading.deviceId]?[dayKey];
        if (existing == null || rwd.reading.createdAt > existing.reading.createdAt) {
          deviceDayReadings.putIfAbsent(rwd.reading.deviceId, () => {})[dayKey] = rwd;
        }
      }

      // Index replacements by device
      final Map<String, List<SupabaseMeterReplacement>> replacementsByDevice = {};
      for (final rep in replacements) {
        replacementsByDevice.putIfAbsent(rep.deviceId, () => []).add(rep);
      }

      // Map operator assignments
      final Map<String, SupabaseDevice> deviceMap = {for (final d in devices) d.id: d};
      final Map<String, List<SupabaseDevice>> operatorDevicesMap = {};
      for (final asgn in activeAssignments) {
        final opId = asgn['operator_id'] as String?;
        final devId = asgn['device_id'] as String?;
        if (opId != null && devId != null && deviceMap.containsKey(devId)) {
          final dev = deviceMap[devId]!;
          if (dev.isActive) {
            operatorDevicesMap.putIfAbsent(opId, () => []).add(dev);
          }
        }
      }

      // 1. Sheet 1: Energy_Abstract
      _buildEnergyAbstractSheet(
        excel: excel,
        startDate: startDate,
        endDate: endDate,
        cycleDates: cycleDates,
        devices: devices,
        deviceDayReadings: deviceDayReadings,
        replacementsByDevice: replacementsByDevice,
      );

      // 2. Sheet 2: SMS_Divisions
      _buildSmsDivisionsSheet(
        excel: excel,
        startDate: startDate,
        endDate: endDate,
        cycleDates: cycleDates,
        devices: devices,
        operators: operators,
        operatorDevicesMap: operatorDevicesMap,
        deviceDayReadings: deviceDayReadings,
        replacementsByDevice: replacementsByDevice,
      );

      // 3. Sheet 3: SID_Dedusting
      _buildDedustingSheet(
        excel: excel,
        startDate: startDate,
        endDate: endDate,
        cycleDates: cycleDates,
        devices: devices,
        operators: operators,
        operatorDevicesMap: operatorDevicesMap,
        deviceDayReadings: deviceDayReadings,
        replacementsByDevice: replacementsByDevice,
      );

      // 4. Sheet 4: Water_Meters
      _buildWaterSheet(
        excel: excel,
        startDate: startDate,
        endDate: endDate,
        cycleDates: cycleDates,
        devices: devices,
        operators: operators,
        operatorDevicesMap: operatorDevicesMap,
        deviceDayReadings: deviceDayReadings,
        replacementsByDevice: replacementsByDevice,
      );

      excel.delete('Sheet1');

      final bytes = excel.save();
      if (bytes == null) return null;

      final monthStr = DateFormat('MMM_yyyy').format(startDate);
      final fileName = 'Monthly_Plant_Report_$monthStr.xlsx';
      return await _saveFile(bytes, fileName);
    } catch (e) {
      debugPrint('Monthly Report Export Error: $e');
      return null;
    }
  }


  /// Generates and exports the complete Financial Year statement (12 Months: April to March + Total FY).
  Future<String?> generateAndExportFinancialYearStatement({
    required int fyStartYear,
    required SupabaseDevicesRepository devicesRepo,
    required SupabaseOperatorsRepository operatorsRepo,
    required SupabaseReadingsRepository readingsRepo,
    required SupabaseMeterReplacementRepository replacementsRepo,
  }) async {
    final startDate = DateTime(fyStartYear, 4, 1);
    final endDate = DateTime(fyStartYear + 1, 4, 1);
    final fromDateMs = AppDateUtils.toLocalMidnightUtcMs(startDate.subtract(const Duration(days: 2)));
    final toDateMs = AppDateUtils.toLocalMidnightUtcMs(endDate) + 86399999;

    final results = await Future.wait([
      devicesRepo.getAll(),
      operatorsRepo.getAll(),
      devicesRepo.getAllActiveAssignments(),
      replacementsRepo.getAll(),
      readingsRepo.search(
        readingType: 'day',
        fromDateMs: fromDateMs,
        toDateMs: toDateMs,
        limit: 10000,
      ),
    ]);

    final devices = results[0] as List<SupabaseDevice>;
    final operators = results[1] as List<SupabaseOperator>;
    final activeAssignments = results[2] as List<Map<String, dynamic>>;
    final replacements = results[3] as List<SupabaseMeterReplacement>;
    final readings = results[4] as List<SupabaseReadingWithDetails>;

    return exportFinancialYearStatementToExcel(
      fyStartYear: fyStartYear,
      devices: devices,
      operators: operators,
      activeAssignments: activeAssignments,
      readings: readings,
      replacements: replacements,
    );
  }

  /// Generates the 4-sheet Financial Year statement workbook.
  Future<String?> exportFinancialYearStatementToExcel({
    required int fyStartYear,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required List<Map<String, dynamic>> activeAssignments,
    required List<SupabaseReadingWithDetails> readings,
    required List<SupabaseMeterReplacement> replacements,
  }) async {
    try {
      final excel = Excel.createExcel();

      // Index 1st of month readings by device and 'year_month'
      final Map<String, Map<String, SupabaseReadingWithDetails>> deviceMonthReadings = {};
      final Map<String, Map<String, List<SupabaseReadingWithDetails>>> allDeviceMonthReadings = {};
      for (final rwd in readings) {
        if (rwd.reading.readingType != 'day') continue;
        final dt = DateTime.fromMillisecondsSinceEpoch(rwd.reading.readingDate, isUtc: true).toLocal();
        final ymKey = '${dt.year}_${dt.month}';
        allDeviceMonthReadings.putIfAbsent(rwd.reading.deviceId, () => {}).putIfAbsent(ymKey, () => []).add(rwd);
        if (dt.day == 1) {
          final existing = deviceMonthReadings[rwd.reading.deviceId]?[ymKey];
          if (existing == null || rwd.reading.createdAt > existing.reading.createdAt) {
            deviceMonthReadings.putIfAbsent(rwd.reading.deviceId, () => {})[ymKey] = rwd;
          }
        }
      }

      // Index replacements
      final Map<String, List<SupabaseMeterReplacement>> replacementsByDevice = {};
      for (final rep in replacements) {
        replacementsByDevice.putIfAbsent(rep.deviceId, () => []).add(rep);
      }

      // Map operator assignments
      final Map<String, SupabaseDevice> deviceMap = {for (final d in devices) d.id: d};
      final Map<String, List<SupabaseDevice>> operatorDevicesMap = {};
      for (final asgn in activeAssignments) {
        final opId = asgn['operator_id'] as String?;
        final devId = asgn['device_id'] as String?;
        if (opId != null && devId != null && deviceMap.containsKey(devId)) {
          final dev = deviceMap[devId]!;
          if (dev.isActive) {
            operatorDevicesMap.putIfAbsent(opId, () => []).add(dev);
          }
        }
      }

      // 1. Sheet 1: Energy_Abstract
      _buildFyEnergyAbstractSheet(
        excel: excel,
        fyStartYear: fyStartYear,
        devices: devices,
        deviceMonthReadings: deviceMonthReadings,
        allDeviceMonthReadings: allDeviceMonthReadings,
        replacementsByDevice: replacementsByDevice,
      );

      // 2. Sheet 2: SMS_Divisions
      _buildFySmsDivisionsSheet(
        excel: excel,
        fyStartYear: fyStartYear,
        devices: devices,
        operators: operators,
        operatorDevicesMap: operatorDevicesMap,
        deviceMonthReadings: deviceMonthReadings,
        allDeviceMonthReadings: allDeviceMonthReadings,
        replacementsByDevice: replacementsByDevice,
      );

      // 3. Sheet 3: SID_Dedusting
      _buildFyDedustingSheet(
        excel: excel,
        fyStartYear: fyStartYear,
        devices: devices,
        operators: operators,
        operatorDevicesMap: operatorDevicesMap,
        deviceMonthReadings: deviceMonthReadings,
        allDeviceMonthReadings: allDeviceMonthReadings,
        replacementsByDevice: replacementsByDevice,
      );

      // 4. Sheet 4: Water_Meters
      _buildFyWaterSheet(
        excel: excel,
        fyStartYear: fyStartYear,
        devices: devices,
        operators: operators,
        operatorDevicesMap: operatorDevicesMap,
        deviceMonthReadings: deviceMonthReadings,
        allDeviceMonthReadings: allDeviceMonthReadings,
        replacementsByDevice: replacementsByDevice,
      );

      excel.delete('Sheet1');

      final bytes = excel.save();
      if (bytes == null) return null;

      final nextYearShort = (fyStartYear + 1).toString().substring(2);
      final fileName = 'Financial_Year_Report_FY${fyStartYear}_$nextYearShort.xlsx';
      return await _saveFile(bytes, fileName);
    } catch (e) {
      debugPrint('Financial Year Report Export Error: $e');
      return null;
    }
  }

  void _buildFyEnergyAbstractSheet({
    required Excel excel,
    required int fyStartYear,
    required List<SupabaseDevice> devices,
    required Map<String, Map<String, SupabaseReadingWithDetails>> deviceMonthReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
    Map<String, Map<String, List<SupabaseReadingWithDetails>>> allDeviceMonthReadings = const {},
  }) {
    final sheet = excel['Energy_Abstract'];
    final energyDevices = devices
        .where((d) => d.isActive && (d.isEnergy || (!d.isDedusting && !d.isWater)))
        .toList();

    int energyPriority(String name) {
      final lower = name.toLowerCase().trim();
      if (lower.contains('132')) return 1;
      if (lower == 'sid' || lower.startsWith('sid ')) return 2;
      if (lower.contains('pellet')) return 3;
      if (lower.contains('ballmill')) return 4;
      if (lower.contains('solar')) return 5;
      if (lower.contains('rolling')) return 6;
      if (lower.contains('sms 1') || lower.contains('sms1')) return 7;
      if (lower == 'sms2' || lower.contains('sms 2')) return 8;
      if (lower == 'sms 3' || lower.contains('sms3')) return 9;
      if (lower == 'sms4' || lower.contains('sms 4')) return 10;
      return 100;
    }

    energyDevices.sort((a, b) => energyPriority(a.name).compareTo(energyPriority(b.name)));
    final nextYearShort = (fyStartYear + 1).toString().substring(2);

    _renderFyTable(
      sheet: sheet,
      tableTitle: 'PLANT ENERGY METERS - FINANCIAL YEAR STATEMENT (FY $fyStartYear-$nextYearShort)',
      cycleSubtitle: 'Billing Cycle: Initial Reading on 1st of Month to Final Reading on 1st of Next Month (Day Readings Only)',
      fyStartYear: fyStartYear,
      devices: energyDevices,
      deviceMonthReadings: deviceMonthReadings,
      allDeviceMonthReadings: allDeviceMonthReadings,
      replacementsByDevice: replacementsByDevice,
    );
  }

  void _buildFySmsDivisionsSheet({
    required Excel excel,
    required int fyStartYear,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required Map<String, List<SupabaseDevice>> operatorDevicesMap,
    required Map<String, Map<String, SupabaseReadingWithDetails>> deviceMonthReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
    Map<String, Map<String, List<SupabaseReadingWithDetails>>> allDeviceMonthReadings = const {},
  }) {
    final sheet = excel['SMS_Divisions'];
    final nextYearShort = (fyStartYear + 1).toString().substring(2);

    sheet.appendRow([TextCellValue('SMS DIVISIONS - FINANCIAL YEAR STATEMENT (FY $fyStartYear-$nextYearShort)')]);
    sheet.appendRow([TextCellValue('Separate Table for Each Operator | Billing Cycle: 1st of Month to 1st of Next Month')]);
    sheet.appendRow([TextCellValue('')]);

    final targetCodes = ['sms2', 'sms3', 'sms4'];
    for (final code in targetCodes) {
      final op = operators.firstWhere(
        (o) => o.username.toLowerCase().replaceAll(' ', '') == code,
        orElse: () => SupabaseOperator(
          id: '',
          username: code,
          fullName: code.toUpperCase(),
          passwordHash: '',
          role: 'operator',
          isActive: true,
          createdAt: 0,
        ),
      );

      final assigned = op.id.isNotEmpty ? (operatorDevicesMap[op.id] ?? []) : <SupabaseDevice>[];
      final sectionDevices = devices.where((d) {
        if (!d.isActive) return false;
        if (assigned.any((ad) => ad.id == d.id)) return true;
        final dName = d.name.toLowerCase().replaceAll(' ', '');
        return dName.startsWith(code) || dName.contains(code);
      }).toSet().toList();

      sectionDevices.sort((a, b) {
        if (a.name.toUpperCase().replaceAll(' ', '') == code.toUpperCase()) return -1;
        if (b.name.toUpperCase().replaceAll(' ', '') == code.toUpperCase()) return 1;
        return a.name.compareTo(b.name);
      });

      if (sectionDevices.isNotEmpty) {
        _renderFyTable(
          sheet: sheet,
          tableTitle: '${op.fullName.toUpperCase()} (${code.toUpperCase()}) - FINANCIAL YEAR STATEMENT',
          cycleSubtitle: 'Billing Cycle: 1st of Month to 1st of Next Month',
          fyStartYear: fyStartYear,
          devices: sectionDevices,
          deviceMonthReadings: deviceMonthReadings,
          allDeviceMonthReadings: allDeviceMonthReadings,
          replacementsByDevice: replacementsByDevice,
        );
      }
    }
  }

  void _buildFyDedustingSheet({
    required Excel excel,
    required int fyStartYear,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required Map<String, List<SupabaseDevice>> operatorDevicesMap,
    required Map<String, Map<String, SupabaseReadingWithDetails>> deviceMonthReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
    Map<String, Map<String, List<SupabaseReadingWithDetails>>> allDeviceMonthReadings = const {},
  }) {
    final sheet = excel['SID_Dedusting'];
    final nextYearShort = (fyStartYear + 1).toString().substring(2);

    sheet.appendRow([TextCellValue('SPONGE IRON POLLUTION / DEDUSTING - FINANCIAL YEAR STATEMENT (FY $fyStartYear-$nextYearShort)')]);
    sheet.appendRow([TextCellValue('Sponge Iron Pollution Equipment | Billing Cycle: 1st of Month to 1st of Next Month')]);
    sheet.appendRow([TextCellValue('')]);

    final spongeOp = operators.firstWhere(
      (o) => o.username.toLowerCase() == 'sponge',
      orElse: () => const SupabaseOperator(
        id: '',
        username: 'Sponge',
        fullName: 'Sponge Iron',
        passwordHash: '',
        role: 'operator',
        isActive: true,
        createdAt: 0,
      ),
    );

    final assigned = spongeOp.id.isNotEmpty ? (operatorDevicesMap[spongeOp.id] ?? []) : <SupabaseDevice>[];
    final dedustDevices = devices.where((d) {
      if (!d.isActive || !d.isDedusting) return false;
      if (assigned.any((ad) => ad.id == d.id)) return true;
      return !d.name.toUpperCase().contains('SMS');
    }).toSet().toList()..sort((a, b) => a.name.compareTo(b.name));

    if (dedustDevices.isNotEmpty) {
      _renderFyTable(
        sheet: sheet,
        tableTitle: 'SPONGE IRON POLLUTION EQUIPMENT (OPERATOR: SPONGE)',
        cycleSubtitle: 'Billing Cycle: 1st of Month to 1st of Next Month',
        fyStartYear: fyStartYear,
        devices: dedustDevices,
        deviceMonthReadings: deviceMonthReadings,
        allDeviceMonthReadings: allDeviceMonthReadings,
        replacementsByDevice: replacementsByDevice,
      );
    }
  }

  void _buildFyWaterSheet({
    required Excel excel,
    required int fyStartYear,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required Map<String, List<SupabaseDevice>> operatorDevicesMap,
    required Map<String, Map<String, SupabaseReadingWithDetails>> deviceMonthReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
    Map<String, Map<String, List<SupabaseReadingWithDetails>>> allDeviceMonthReadings = const {},
  }) {
    final sheet = excel['Water_Meters'];
    final nextYearShort = (fyStartYear + 1).toString().substring(2);

    sheet.appendRow([TextCellValue('PLANT WATER METERS - FINANCIAL YEAR STATEMENT (FY $fyStartYear-$nextYearShort)')]);
    sheet.appendRow([TextCellValue('Separate Table for Each Operator | Billing Cycle: 1st of Month to 1st of Next Month')]);
    sheet.appendRow([TextCellValue('')]);

    final allWater = devices.where((d) => d.isActive && d.isWater).toList();
    final sidWater = allWater.where((d) => d.name.toUpperCase().contains('SID')).toList()..sort((a, b) => a.name.compareTo(b.name));
    final rmdWater = allWater.where((d) => !d.name.toUpperCase().contains('SID')).toList()..sort((a, b) => a.name.compareTo(b.name));

    if (sidWater.isNotEmpty) {
      _renderFyTable(
        sheet: sheet,
        tableTitle: 'SPONGE IRON WATER METERS (OPERATOR: SPONGE)',
        cycleSubtitle: 'Billing Cycle: 1st of Month to 1st of Next Month',
        fyStartYear: fyStartYear,
        devices: sidWater,
        deviceMonthReadings: deviceMonthReadings,
        allDeviceMonthReadings: allDeviceMonthReadings,
        replacementsByDevice: replacementsByDevice,
      );
    }

    if (rmdWater.isNotEmpty) {
      _renderFyTable(
        sheet: sheet,
        tableTitle: 'ROLLING MILL WATER METERS (OPERATOR: ROLLINGMILL)',
        cycleSubtitle: 'Billing Cycle: 1st of Month to 1st of Next Month',
        fyStartYear: fyStartYear,
        devices: rmdWater,
        deviceMonthReadings: deviceMonthReadings,
        allDeviceMonthReadings: allDeviceMonthReadings,
        replacementsByDevice: replacementsByDevice,
      );
    }
  }

  void _renderFyTable({
    required Sheet sheet,
    required String tableTitle,
    required String cycleSubtitle,
    required int fyStartYear,
    required List<SupabaseDevice> devices,
    required Map<String, Map<String, SupabaseReadingWithDetails>> deviceMonthReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
    Map<String, Map<String, List<SupabaseReadingWithDetails>>> allDeviceMonthReadings = const {},
  }) {
    if (devices.isEmpty) return;

    sheet.appendRow([TextCellValue(tableTitle)]);
    sheet.appendRow([TextCellValue(cycleSubtitle)]);

    final List<_ColumnDef> colDefs = [];

    for (final d in devices) {
      if (d.requiresHeatDay || d.dayMatrix.split(',').length > 1) {
        final rawUnits = (d.dayMatrix.isNotEmpty ? d.dayMatrix : d.matrix)
            .split(',')
            .map((s) => s.trim().toUpperCase())
            .where((s) => s.isNotEmpty)
            .toList();
        final units = rawUnits.isNotEmpty ? rawUnits : ['KWH', 'KWHLT'];
        for (final u in units) {
          final mfStr = d.multiplicationFactor > 0 ? d.multiplicationFactor.toStringAsFixed(0) : '1';
          if (u == 'PF') {
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'PF',
              type: _ColumnType.pf,
            ));
          } else if (u == 'MD') {
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'MD Reading',
              type: _ColumnType.mdReading,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'MF',
              type: _ColumnType.mf,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'MD Recorded',
              type: _ColumnType.mdRecorded,
            ));
          } else {
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: '$u Initial (01st)',
              type: _ColumnType.reading,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: '$u Final (01st)',
              type: _ColumnType.reading,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: '$u Diff',
              type: _ColumnType.diff,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'MF',
              type: _ColumnType.mf,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: '$u Units',
              type: _ColumnType.consumption,
            ));
          }
        }
      } else {
        final unit = d.singleMetric.isNotEmpty ? d.singleMetric : 'KWH';
        final mfVal = d.multiplicationFactor > 0 ? d.multiplicationFactor : 1.0;
        final mfLabel = mfVal > 0 ? mfVal.toStringAsFixed(mfVal % 1 == 0 ? 0 : 2) : '1';
        if (unit == 'MD') {
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MD Reading',
            type: _ColumnType.mdReading,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MF',
            type: _ColumnType.mf,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MD Recorded',
            type: _ColumnType.mdRecorded,
          ));
        } else if (unit == 'PF') {
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'PF',
            type: _ColumnType.pf,
          ));
        } else {
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'Initial (01st)',
            type: _ColumnType.reading,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'Final (01st)',
            type: _ColumnType.reading,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'Diff',
            type: _ColumnType.diff,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MF',
            type: _ColumnType.mf,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'Units',
            type: _ColumnType.consumption,
          ));
        }
      }
    }

    // Header 1: Device Names
    final hRow1 = <CellValue?>[TextCellValue('Billing Month / Period')];
    for (final col in colDefs) {
      hRow1.add(TextCellValue(col.headerDevice));
    }
    sheet.appendRow(hRow1);

    // Header 2: Metrics
    final hRow2 = <CellValue?>[TextCellValue('')];
    for (final col in colDefs) {
      hRow2.add(TextCellValue(col.headerMetric));
    }
    sheet.appendRow(hRow2);

    // 12 FY Month Rows
    final List<Map<_ColumnDef, double?>> monthlyDiffs = [];
    final List<Map<_ColumnDef, double?>> monthlyConsumps = [];
    final List<Map<_ColumnDef, double?>> monthlyMdReadings = [];
    final List<Map<_ColumnDef, double?>> monthlyPfReadings = [];

    for (int i = 0; i < 12; i++) {
      final calM = ((i + 3) % 12) + 1;
      final calY = i < 9 ? fyStartYear : fyStartYear + 1;
      final nextCalM = ((i + 4) % 12) + 1;
      final nextCalY = (i + 1) < 9 ? fyStartYear : fyStartYear + 1;

      final initDate = DateTime(calY, calM, 1);
      final finalDate = DateTime(nextCalY, nextCalM, 1);
      final mName = DateFormat('MMMM yyyy').format(initDate);
      final initLabel = DateFormat('01-MMM').format(initDate);
      final finalLabel = DateFormat('01-MMM').format(finalDate);
      final monthTitle = '$mName ($initLabel to $finalLabel)';

      final row = <CellValue?>[TextCellValue(monthTitle)];
      final Map<_ColumnDef, double?> rowDiffMap = {};
      final Map<_ColumnDef, double?> rowConsumpMap = {};
      final Map<_ColumnDef, double?> rowMdMap = {};
      final Map<_ColumnDef, double?> rowPfMap = {};

      for (int cIdx = 0; cIdx < colDefs.length; cIdx++) {
        final col = colDefs[cIdx];
        final d = col.device;
        final rInit = deviceMonthReadings[d.id]?['${calY}_${calM}'];
        final rFinal = deviceMonthReadings[d.id]?['${nextCalY}_${nextCalM}'];

        final initVals = rInit != null ? ReadingCalculationUtils.parseValues(rInit.reading.readingValues) : null;
        final finalVals = rFinal != null ? ReadingCalculationUtils.parseValues(rFinal.reading.readingValues) : null;

        final initVal = initVals?[col.unit] ?? initVals?[col.unit.toLowerCase()];
        final finalVal = finalVals?[col.unit] ?? finalVals?[col.unit.toLowerCase()];

        final factor = ReadingCalculationUtils.resolveEffectiveFactor(
          readingDateMs: rFinal?.reading.readingDate ?? rInit?.reading.readingDate ?? AppDateUtils.toLocalMidnightUtcMs(finalDate),
          unit: col.unit,
          readingType: 'day',
          currentDeviceMf: d.multiplicationFactor,
          dayUnitFactorsJson: d.dayUnitFactors,
          heatUnitFactorsJson: d.heatUnitFactors,
          replacements: replacementsByDevice[d.id] ?? [],
        );

        double? diff;
        if (finalVal != null && initVal != null) {
          diff = ReadingCalculationUtils.calculateDifference(finalVal, initVal);
        }
        final consump = diff != null ? diff * factor : null;

        if (col.type == _ColumnType.diff) {
          rowDiffMap[col] = diff;
        } else if (col.type == _ColumnType.consumption) {
          rowConsumpMap[col] = consump;
        } else if (col.type == _ColumnType.mdReading) {
          double? maxMd;
          final mReadings = allDeviceMonthReadings[d.id]?['${calY}_${calM}'] ?? [];
          for (final mr in mReadings) {
            final mVals = ReadingCalculationUtils.parseValues(mr.reading.readingValues);
            final v = mVals[col.unit] ?? mVals[col.unit.toLowerCase()];
            if (v != null && (maxMd == null || v > maxMd)) {
              maxMd = v;
            }
          }
          final mdVal = maxMd ?? finalVal ?? initVal;
          rowMdMap[col] = mdVal;
        } else if (col.type == _ColumnType.pf) {
          rowPfMap[col] = finalVal ?? initVal;
        }

        switch (col.type) {
          case _ColumnType.reading:
            // Check if column is Initial or Final
            if (col.headerMetric.contains('Initial')) {
              row.add(_formatDoubleCell(initVal));
            } else {
              row.add(_formatDoubleCell(finalVal));
            }
            break;
          case _ColumnType.diff:
            row.add(_formatDoubleCell(diff));
            break;
          case _ColumnType.mf:
            row.add(DoubleCellValue(factor));
            break;
          case _ColumnType.consumption:
            row.add(_formatDoubleCell(consump));
            break;
          case _ColumnType.pf:
            row.add(_formatDoubleCell(finalVal ?? initVal));
            break;
          case _ColumnType.mdReading:
            row.add(_formatDoubleCell(rowMdMap[col]));
            break;
          case _ColumnType.mdRecorded:
            final md = rowMdMap[col] ?? finalVal ?? initVal;
            row.add(_formatDoubleCell(md != null ? md * factor : null));
            break;
        }
      }

      monthlyDiffs.add(rowDiffMap);
      monthlyConsumps.add(rowConsumpMap);
      monthlyMdReadings.add(rowMdMap);
      monthlyPfReadings.add(rowPfMap);
      sheet.appendRow(row);
    }

    // Total Financial Year Row
    final nextYearShort = (fyStartYear + 1).toString().substring(2);
    final totalRow = <CellValue?>[TextCellValue('TOTAL FINANCIAL YEAR (FY $fyStartYear-$nextYearShort)')];

    for (final col in colDefs) {
      if (col.type == _ColumnType.diff) {
        double sum = 0.0;
        bool hasAny = false;
        for (final m in monthlyDiffs) {
          final v = m[col];
          if (v != null) { sum += v; hasAny = true; }
        }
        totalRow.add(hasAny ? _formatDoubleCell(sum) : TextCellValue(''));
      } else if (col.type == _ColumnType.consumption) {
        double sum = 0.0;
        bool hasAny = false;
        for (final m in monthlyConsumps) {
          final v = m[col];
          if (v != null) { sum += v; hasAny = true; }
        }
        totalRow.add(hasAny ? _formatDoubleCell(sum) : TextCellValue(''));
      } else if (col.type == _ColumnType.mdReading) {
        double maxMd = 0.0;
        bool hasAny = false;
        for (final m in monthlyMdReadings) {
          final v = m[col];
          if (v != null) {
            if (!hasAny || v > maxMd) { maxMd = v; }
            hasAny = true;
          }
        }
        totalRow.add(hasAny ? _formatDoubleCell(maxMd) : TextCellValue(''));
      } else if (col.type == _ColumnType.mdRecorded) {
        // Max MD Recorded
        double maxMdRec = 0.0;
        bool hasAny = false;
        for (final m in monthlyMdReadings) {
          final v = m[col];
          if (v != null) {
            final factor = col.device.multiplicationFactor > 0 ? col.device.multiplicationFactor : 1.0;
            final rec = v * factor;
            if (!hasAny || rec > maxMdRec) { maxMdRec = rec; }
            hasAny = true;
          }
        }
        totalRow.add(hasAny ? _formatDoubleCell(maxMdRec) : TextCellValue(''));
      } else if (col.type == _ColumnType.pf) {
        double sumPf = 0.0;
        int countPf = 0;
        for (final m in monthlyPfReadings) {
          final v = m[col];
          if (v != null) { sumPf += v; countPf++; }
        }
        totalRow.add(countPf > 0 ? _formatDoubleCell(sumPf / countPf) : TextCellValue(''));
      } else if (col.type == _ColumnType.mf) {
        final factor = col.device.multiplicationFactor > 0 ? col.device.multiplicationFactor : 1.0;
        totalRow.add(DoubleCellValue(factor));
      } else if (col.type == _ColumnType.reading) {
        if (col.headerMetric.contains('Initial')) {
          // April initial reading
          final rInit = deviceMonthReadings[col.device.id]?['${fyStartYear}_4'];
          final vals = rInit != null ? ReadingCalculationUtils.parseValues(rInit.reading.readingValues) : null;
          final v = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
          totalRow.add(_formatDoubleCell(v));
        } else {
          // March final reading
          final rFinal = deviceMonthReadings[col.device.id]?['${fyStartYear + 1}_4'];
          final vals = rFinal != null ? ReadingCalculationUtils.parseValues(rFinal.reading.readingValues) : null;
          final v = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
          totalRow.add(_formatDoubleCell(v));
        }
      } else {
        totalRow.add(TextCellValue('-'));
      }
    }
    sheet.appendRow(totalRow);

    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([TextCellValue('')]);
  }

  void _buildEnergyAbstractSheet({
    required Excel excel,
    required DateTime startDate,
    required DateTime endDate,
    required List<DateTime> cycleDates,
    required List<SupabaseDevice> devices,
    required Map<String, Map<DateTime, SupabaseReadingWithDetails>> deviceDayReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
  }) {
    final sheet = excel['Energy_Abstract'];
    final energyDevices = devices
        .where((d) => d.isActive && (d.isEnergy || (!d.isDedusting && !d.isWater)))
        .toList();

    int energyPriority(String name) {
      final lower = name.toLowerCase().trim();
      if (lower.contains('132')) return 1;
      if (lower == 'sid' || lower.startsWith('sid ')) return 2;
      if (lower.contains('pellet')) return 3;
      if (lower.contains('ballmill')) return 4;
      if (lower.contains('solar')) return 5;
      if (lower.contains('rolling')) return 6;
      if (lower.contains('sms 1') || lower.contains('sms1')) return 7;
      if (lower == 'sms2' || lower.contains('sms 2')) return 8;
      if (lower == 'sms 3' || lower.contains('sms3')) return 9;
      if (lower == 'sms4' || lower.contains('sms 4')) return 10;
      return 100;
    }

    energyDevices.sort((a, b) => energyPriority(a.name).compareTo(energyPriority(b.name)));

    final startStr = DateFormat('dd-MMM-yyyy').format(startDate);
    final endStr = DateFormat('dd-MMM-yyyy').format(endDate);
    final monthHeader = DateFormat('MMMM yyyy').format(startDate);

    _renderOperatorTable(
      sheet: sheet,
      tableTitle: 'PLANT ENERGY METERS - MONTHLY ABSTRACT ($monthHeader)',
      cycleSubtitle: 'Billing Cycle: $startStr to $endStr (Day Readings Only)',
      devices: energyDevices,
      cycleDates: cycleDates,
      deviceDayReadings: deviceDayReadings,
      replacementsByDevice: replacementsByDevice,
    );
  }

  void _buildSmsDivisionsSheet({
    required Excel excel,
    required DateTime startDate,
    required DateTime endDate,
    required List<DateTime> cycleDates,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required Map<String, List<SupabaseDevice>> operatorDevicesMap,
    required Map<String, Map<DateTime, SupabaseReadingWithDetails>> deviceDayReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
  }) {
    final sheet = excel['SMS_Divisions'];
    final startStr = DateFormat('dd-MMM-yyyy').format(startDate);
    final endStr = DateFormat('dd-MMM-yyyy').format(endDate);

    sheet.appendRow([TextCellValue('SMS DIVISIONS - MONTHLY DAY READINGS')]);
    sheet.appendRow([TextCellValue('Billing Cycle: $startStr to $endStr')]);
    sheet.appendRow([TextCellValue('')]);

    final smsOperators = operators
        .where((op) =>
            op.username.toLowerCase().contains('sms') ||
            op.fullName.toLowerCase().contains('sms'))
        .toList()
      ..sort((a, b) => a.username.compareTo(b.username));

    final targetCodes = ['sms2', 'sms3', 'sms4'];
    final List<({String title, String opId, String code})> sections = [];
    if (smsOperators.isNotEmpty) {
      for (final op in smsOperators) {
        sections.add((
          title: '${op.fullName.toUpperCase()} (${op.username.toUpperCase()}) - DAY READINGS',
          opId: op.id,
          code: op.username.toLowerCase().replaceAll(' ', ''),
        ));
      }
    } else {
      for (final code in targetCodes) {
        sections.add((
          title: '${code.toUpperCase()} DIVISION - DAY READINGS',
          opId: '',
          code: code,
        ));
      }
    }

    for (final sec in sections) {
      final assigned = sec.opId.isNotEmpty ? (operatorDevicesMap[sec.opId] ?? []) : <SupabaseDevice>[];
      final sectionDevices = devices.where((d) {
        if (!d.isActive) return false;
        if (assigned.any((ad) => ad.id == d.id)) return true;
        final dName = d.name.toLowerCase().replaceAll(' ', '');
        return dName.startsWith(sec.code) || dName.contains(sec.code);
      }).toSet().toList();

      sectionDevices.sort((a, b) {
        if (a.requiresHeatDay && !b.requiresHeatDay) return -1;
        if (!a.requiresHeatDay && b.requiresHeatDay) return 1;
        return a.name.compareTo(b.name);
      });

      if (sectionDevices.isNotEmpty) {
        _renderOperatorTable(
          sheet: sheet,
          tableTitle: sec.title,
          cycleSubtitle: 'Billing Cycle: $startStr to $endStr',
          devices: sectionDevices,
          cycleDates: cycleDates,
          deviceDayReadings: deviceDayReadings,
          replacementsByDevice: replacementsByDevice,
        );
      }
    }
  }

  void _buildDedustingSheet({
    required Excel excel,
    required DateTime startDate,
    required DateTime endDate,
    required List<DateTime> cycleDates,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required Map<String, List<SupabaseDevice>> operatorDevicesMap,
    required Map<String, Map<DateTime, SupabaseReadingWithDetails>> deviceDayReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
  }) {
    final sheet = excel['SID_Dedusting'];
    final startStr = DateFormat('dd-MMM-yyyy').format(startDate);
    final endStr = DateFormat('dd-MMM-yyyy').format(endDate);

    sheet.appendRow([TextCellValue('SPONGE IRON POLLUTION / DEDUSTING EQUIPMENT - MONTHLY REPORT')]);
    sheet.appendRow([TextCellValue('Billing Cycle: $startStr to $endStr')]);
    sheet.appendRow([TextCellValue('')]);

    final allDedustingDevices = devices.where((d) => d.isActive && d.isDedusting).toList();
    final dedustingOperators = operators.where((op) =>
        (operatorDevicesMap[op.id] ?? []).any((d) => d.isDedusting)).toList();

    if (dedustingOperators.isNotEmpty) {
      for (final op in dedustingOperators) {
        final opDevices = (operatorDevicesMap[op.id] ?? [])
            .where((d) => d.isActive && d.isDedusting)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        if (opDevices.isNotEmpty) {
          _renderOperatorTable(
            sheet: sheet,
            tableTitle: 'SPONGE IRON POLLUTION / DEDUSTING (${op.fullName.toUpperCase()})',
            cycleSubtitle: 'Billing Cycle: $startStr to $endStr',
            devices: opDevices,
            cycleDates: cycleDates,
            deviceDayReadings: deviceDayReadings,
            replacementsByDevice: replacementsByDevice,
          );
        }
      }
    } else {
      allDedustingDevices.sort((a, b) => a.name.compareTo(b.name));
      if (allDedustingDevices.isNotEmpty) {
        _renderOperatorTable(
          sheet: sheet,
          tableTitle: 'SPONGE IRON POLLUTION / DEDUSTING EQUIPMENT',
          cycleSubtitle: 'Billing Cycle: $startStr to $endStr',
          devices: allDedustingDevices,
          cycleDates: cycleDates,
          deviceDayReadings: deviceDayReadings,
          replacementsByDevice: replacementsByDevice,
        );
      }
    }
  }

  void _buildWaterSheet({
    required Excel excel,
    required DateTime startDate,
    required DateTime endDate,
    required List<DateTime> cycleDates,
    required List<SupabaseDevice> devices,
    required List<SupabaseOperator> operators,
    required Map<String, List<SupabaseDevice>> operatorDevicesMap,
    required Map<String, Map<DateTime, SupabaseReadingWithDetails>> deviceDayReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
  }) {
    final sheet = excel['Water_Meters'];
    final startStr = DateFormat('dd-MMM-yyyy').format(startDate);
    final endStr = DateFormat('dd-MMM-yyyy').format(endDate);

    sheet.appendRow([TextCellValue('PLANT WATER METERS - MONTHLY REPORT')]);
    sheet.appendRow([TextCellValue('Billing Cycle: $startStr to $endStr')]);
    sheet.appendRow([TextCellValue('')]);

    final allWaterDevices = devices.where((d) => d.isActive && d.isWater).toList();
    final waterOperators = operators.where((op) =>
        (operatorDevicesMap[op.id] ?? []).any((d) => d.isWater)).toList();

    if (waterOperators.isNotEmpty) {
      for (final op in waterOperators) {
        final opDevices = (operatorDevicesMap[op.id] ?? [])
            .where((d) => d.isActive && d.isWater)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        if (opDevices.isNotEmpty) {
          _renderOperatorTable(
            sheet: sheet,
            tableTitle: 'WATER METERS (${op.fullName.toUpperCase()})',
            cycleSubtitle: 'Billing Cycle: $startStr to $endStr',
            devices: opDevices,
            cycleDates: cycleDates,
            deviceDayReadings: deviceDayReadings,
            replacementsByDevice: replacementsByDevice,
          );
        }
      }
    } else {
      final sidWater = allWaterDevices.where((d) => d.name.toUpperCase().contains('SID')).toList();
      final rmdWater = allWaterDevices.where((d) => !d.name.toUpperCase().contains('SID')).toList();

      if (sidWater.isNotEmpty) {
        _renderOperatorTable(
          sheet: sheet,
          tableTitle: 'SID WATER METERS',
          cycleSubtitle: 'Billing Cycle: $startStr to $endStr',
          devices: sidWater,
          cycleDates: cycleDates,
          deviceDayReadings: deviceDayReadings,
          replacementsByDevice: replacementsByDevice,
        );
      }
      if (rmdWater.isNotEmpty) {
        _renderOperatorTable(
          sheet: sheet,
          tableTitle: 'RMD WATER METERS',
          cycleSubtitle: 'Billing Cycle: $startStr to $endStr',
          devices: rmdWater,
          cycleDates: cycleDates,
          deviceDayReadings: deviceDayReadings,
          replacementsByDevice: replacementsByDevice,
        );
      }
    }
  }

  CellValue _formatDoubleCell(double? val) {
    if (val == null) return TextCellValue('');
    if (val % 1 == 0) {
      return DoubleCellValue(val);
    }
    return DoubleCellValue(double.parse(val.toStringAsFixed(2)));
  }

  void _renderOperatorTable({
    required Sheet sheet,
    required String tableTitle,
    required String cycleSubtitle,
    required List<SupabaseDevice> devices,
    required List<DateTime> cycleDates,
    required Map<String, Map<DateTime, SupabaseReadingWithDetails>> deviceDayReadings,
    required Map<String, List<SupabaseMeterReplacement>> replacementsByDevice,
  }) {
    if (devices.isEmpty) return;

    sheet.appendRow([TextCellValue(tableTitle)]);
    sheet.appendRow([TextCellValue(cycleSubtitle)]);

    final List<_ColumnDef> colDefs = [];

    for (final d in devices) {
      if (d.requiresHeatDay || d.dayMatrix.split(',').length > 1) {
        final rawUnits = (d.dayMatrix.isNotEmpty ? d.dayMatrix : d.matrix)
            .split(',')
            .map((s) => s.trim().toUpperCase())
            .where((s) => s.isNotEmpty)
            .toList();
        final units = rawUnits.isNotEmpty ? rawUnits : ['KWH', 'KWHLT'];
        for (final u in units) {
          final mfStr = d.multiplicationFactor > 0 ? d.multiplicationFactor.toStringAsFixed(0) : '1';
          if (u == 'PF') {
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'PF',
              type: _ColumnType.pf,
            ));
          } else if (u == 'MD') {
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'MD Reading',
              type: _ColumnType.mdReading,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'MF',
              type: _ColumnType.mf,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: 'MD Recorded',
              type: _ColumnType.mdRecorded,
            ));
          } else {
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: '$u Reading',
              type: _ColumnType.reading,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: '$u Diff',
              type: _ColumnType.diff,
            ));
            colDefs.add(_ColumnDef(
              device: d,
              unit: u,
              headerDevice: '${d.name} (MF: $mfStr)',
              headerMetric: '$u Units',
              type: _ColumnType.consumption,
            ));
          }
        }
      } else {
        final unit = d.singleMetric.isNotEmpty ? d.singleMetric : 'KWH';
        final mfLabel = d.multiplicationFactor > 0 ? d.multiplicationFactor.toStringAsFixed(0) : '1';
        if (unit == 'MD') {
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MD Reading',
            type: _ColumnType.mdReading,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MF',
            type: _ColumnType.mf,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MD Recorded',
            type: _ColumnType.mdRecorded,
          ));
        } else if (unit == 'PF') {
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'PF',
            type: _ColumnType.pf,
          ));
        } else {
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'Reading',
            type: _ColumnType.reading,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'Diff',
            type: _ColumnType.diff,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'MF',
            type: _ColumnType.mf,
          ));
          colDefs.add(_ColumnDef(
            device: d,
            unit: unit,
            headerDevice: '${d.name} (MF: $mfLabel)',
            headerMetric: 'Units',
            type: _ColumnType.consumption,
          ));
        }
      }
    }

    // Header Row 1: Device Names
    final headerRow1 = <CellValue?>[TextCellValue('Date')];
    for (final col in colDefs) {
      headerRow1.add(TextCellValue(col.headerDevice));
    }
    sheet.appendRow(headerRow1);

    // Header Row 2: Metrics
    final headerRow2 = <CellValue?>[TextCellValue('')];
    for (final col in colDefs) {
      headerRow2.add(TextCellValue(col.headerMetric));
    }
    sheet.appendRow(headerRow2);

    // Date Rows
    for (int t = 0; t < cycleDates.length; t++) {
      final date = cycleDates[t];
      final prevDate = t > 0 ? cycleDates[t - 1] : date.subtract(const Duration(days: 1));
      final dateStr = DateFormat('dd-MMM-yyyy').format(date);
      final row = <CellValue?>[TextCellValue(dateStr)];

      for (final col in colDefs) {
        final d = col.device;
        final rwd = deviceDayReadings[d.id]?[date];
        final prevRwd = deviceDayReadings[d.id]?[prevDate];

        if (rwd == null) {
          row.add(TextCellValue(''));
          continue;
        }

        final vals = ReadingCalculationUtils.parseValues(rwd.reading.readingValues);
        final prevVals = prevRwd != null
            ? ReadingCalculationUtils.parseValues(prevRwd.reading.readingValues)
            : null;

        final curVal = vals[col.unit] ?? vals[col.unit.toLowerCase()];
        final prevVal = prevVals?[col.unit] ?? prevVals?[col.unit.toLowerCase()];

        final factor = ReadingCalculationUtils.resolveEffectiveFactor(
          readingDateMs: rwd.reading.readingDate,
          unit: col.unit,
          readingType: 'day',
          currentDeviceMf: d.multiplicationFactor,
          dayUnitFactorsJson: d.dayUnitFactors,
          heatUnitFactorsJson: d.heatUnitFactors,
          replacements: replacementsByDevice[d.id] ?? [],
        );

        double? diff;
        if (curVal != null && prevVal != null) {
          diff = ReadingCalculationUtils.calculateDifference(curVal, prevVal);
        }
        final consump = diff != null ? diff * factor : null;

        switch (col.type) {
          case _ColumnType.reading:
            row.add(_formatDoubleCell(curVal));
            break;
          case _ColumnType.diff:
            row.add(_formatDoubleCell(diff));
            break;
          case _ColumnType.mf:
            row.add(DoubleCellValue(factor));
            break;
          case _ColumnType.consumption:
            row.add(_formatDoubleCell(consump));
            break;
          case _ColumnType.pf:
            row.add(_formatDoubleCell(curVal));
            break;
          case _ColumnType.mdReading:
            row.add(_formatDoubleCell(curVal));
            break;
          case _ColumnType.mdRecorded:
            row.add(_formatDoubleCell(curVal != null ? curVal * factor : null));
            break;
        }
      }
      sheet.appendRow(row);
    }

    // Summary Rows
    final startDateStr = DateFormat('MMM').format(cycleDates.first);
    final endDateStr = DateFormat('MMM').format(cycleDates.last);

    // 1. Initial Reading Row
    final initRow = <CellValue?>[TextCellValue('Initial Reading (01-$startDateStr)')];
    for (final col in colDefs) {
      if (col.type == _ColumnType.reading || col.type == _ColumnType.mdReading) {
        final rwd = deviceDayReadings[col.device.id]?[cycleDates.first];
        final vals = rwd != null ? ReadingCalculationUtils.parseValues(rwd.reading.readingValues) : null;
        final val = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
        initRow.add(_formatDoubleCell(val));
      } else if (col.type == _ColumnType.mdRecorded) {
        final rwd = deviceDayReadings[col.device.id]?[cycleDates.first];
        final vals = rwd != null ? ReadingCalculationUtils.parseValues(rwd.reading.readingValues) : null;
        final val = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
        final factor = rwd != null ? ReadingCalculationUtils.resolveEffectiveFactor(
          readingDateMs: rwd.reading.readingDate,
          unit: col.unit,
          readingType: 'day',
          currentDeviceMf: col.device.multiplicationFactor,
          dayUnitFactorsJson: col.device.dayUnitFactors,
          heatUnitFactorsJson: col.device.heatUnitFactors,
          replacements: replacementsByDevice[col.device.id] ?? [],
        ) : 1.0;
        initRow.add(_formatDoubleCell(val != null ? val * factor : null));
      } else {
        initRow.add(TextCellValue('-'));
      }
    }
    sheet.appendRow(initRow);

    // 2. Final Reading Row
    final finalRow = <CellValue?>[TextCellValue('Final Reading (01-$endDateStr)')];
    for (final col in colDefs) {
      if (col.type == _ColumnType.reading || col.type == _ColumnType.mdReading) {
        final rwd = deviceDayReadings[col.device.id]?[cycleDates.last];
        final vals = rwd != null ? ReadingCalculationUtils.parseValues(rwd.reading.readingValues) : null;
        final val = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
        finalRow.add(_formatDoubleCell(val));
      } else if (col.type == _ColumnType.mdRecorded) {
        final rwd = deviceDayReadings[col.device.id]?[cycleDates.last];
        final vals = rwd != null ? ReadingCalculationUtils.parseValues(rwd.reading.readingValues) : null;
        final val = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
        final factor = rwd != null ? ReadingCalculationUtils.resolveEffectiveFactor(
          readingDateMs: rwd.reading.readingDate,
          unit: col.unit,
          readingType: 'day',
          currentDeviceMf: col.device.multiplicationFactor,
          dayUnitFactorsJson: col.device.dayUnitFactors,
          heatUnitFactorsJson: col.device.heatUnitFactors,
          replacements: replacementsByDevice[col.device.id] ?? [],
        ) : 1.0;
        finalRow.add(_formatDoubleCell(val != null ? val * factor : null));
      } else {
        finalRow.add(TextCellValue('-'));
      }
    }
    sheet.appendRow(finalRow);

    // 3. Net Difference Row
    final netDiffRow = <CellValue?>[TextCellValue('Net Difference')];
    for (final col in colDefs) {
      if (col.type == _ColumnType.diff) {
        final initRwd = deviceDayReadings[col.device.id]?[cycleDates.first];
        final finalRwd = deviceDayReadings[col.device.id]?[cycleDates.last];
        final initVals = initRwd != null ? ReadingCalculationUtils.parseValues(initRwd.reading.readingValues) : null;
        final finalVals = finalRwd != null ? ReadingCalculationUtils.parseValues(finalRwd.reading.readingValues) : null;
        final initVal = initVals?[col.unit] ?? initVals?[col.unit.toLowerCase()];
        final finalVal = finalVals?[col.unit] ?? finalVals?[col.unit.toLowerCase()];
        if (initVal != null && finalVal != null) {
          final net = ReadingCalculationUtils.calculateDifference(finalVal, initVal);
          netDiffRow.add(_formatDoubleCell(net));
        } else {
          netDiffRow.add(TextCellValue(''));
        }
      } else {
        netDiffRow.add(TextCellValue('-'));
      }
    }
    sheet.appendRow(netDiffRow);

    // 4. Total Consumption Row
    final totalRow = <CellValue?>[TextCellValue('Total Consumption')];
    for (final col in colDefs) {
      if (col.type == _ColumnType.consumption) {
        final initRwd = deviceDayReadings[col.device.id]?[cycleDates.first];
        final finalRwd = deviceDayReadings[col.device.id]?[cycleDates.last];
        final initVals = initRwd != null ? ReadingCalculationUtils.parseValues(initRwd.reading.readingValues) : null;
        final finalVals = finalRwd != null ? ReadingCalculationUtils.parseValues(finalRwd.reading.readingValues) : null;
        final initVal = initVals?[col.unit] ?? initVals?[col.unit.toLowerCase()];
        final finalVal = finalVals?[col.unit] ?? finalVals?[col.unit.toLowerCase()];
        if (initVal != null && finalVal != null) {
          final net = ReadingCalculationUtils.calculateDifference(finalVal, initVal);
          final factor = ReadingCalculationUtils.resolveEffectiveFactor(
            readingDateMs: AppDateUtils.toLocalMidnightUtcMs(cycleDates.last),
            unit: col.unit,
            readingType: 'day',
            currentDeviceMf: col.device.multiplicationFactor,
            dayUnitFactorsJson: col.device.dayUnitFactors,
            heatUnitFactorsJson: col.device.heatUnitFactors,
            replacements: replacementsByDevice[col.device.id] ?? [],
          );
          final total = net * factor;
          totalRow.add(_formatDoubleCell(total));
        } else {
          totalRow.add(TextCellValue(''));
        }
      } else {
        totalRow.add(TextCellValue('-'));
      }
    }
    sheet.appendRow(totalRow);

    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([TextCellValue('')]);
    sheet.appendRow([TextCellValue('')]);
  }
}

enum _ColumnType { reading, diff, mf, consumption, pf, mdReading, mdRecorded }

class _ColumnDef {
  final SupabaseDevice device;
  final String unit;
  final String headerDevice;
  final String headerMetric;
  final _ColumnType type;

  _ColumnDef({
    required this.device,
    required this.unit,
    required this.headerDevice,
    required this.headerMetric,
    required this.type,
  });
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
