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

        final sortedForCalc = List<SupabaseReadingWithDetails>.from(deviceReadings);
        sortedForCalc.sort((a, b) => a.reading.createdAt.compareTo(b.reading.createdAt));
        
        final diffMap = <String, Map<String, double?>>{};
        for (int i = 0; i < sortedForCalc.length; i++) {
          final cur = sortedForCalc[i];
          final prev = i > 0 ? sortedForCalc[i - 1] : null;
          final curVals = _parseValues(cur.reading.readingValues);
          final prevVals = prev != null ? _parseValues(prev.reading.readingValues) : <String, double>{};

          final map = <String, double?>{};
          for (final u in allUnits) {
            if (curVals.containsKey(u)) {
              if (prevVals.containsKey(u)) {
                map[u] = curVals[u]! - prevVals[u]!;
              } else {
                map[u] = null;
              }
            }
          }
          diffMap[cur.reading.id] = map;
        }

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

        final sortedForCalc = List<SupabaseReadingWithDetails>.from(deviceReadings);
        sortedForCalc.sort((a, b) => a.reading.createdAt.compareTo(b.reading.createdAt));
        
        final diffMap = <String, Map<String, double?>>{};
        for (int i = 0; i < sortedForCalc.length; i++) {
          final cur = sortedForCalc[i];
          final prev = i > 0 ? sortedForCalc[i - 1] : null;
          final curVals = _parseValues(cur.reading.readingValues);
          final prevVals = prev != null ? _parseValues(prev.reading.readingValues) : <String, double>{};

          final map = <String, double?>{};
          for (final u in allUnits) {
            if (curVals.containsKey(u)) {
              if (prevVals.containsKey(u)) {
                map[u] = curVals[u]! - prevVals[u]!;
              } else {
                map[u] = null;
              }
            }
          }
          diffMap[cur.reading.id] = map;
        }

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
    final fromDateMs = AppDateUtils.toLocalMidnightUtcMs(startDate);
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
          title: '=== ${op.fullName.toUpperCase()} (${op.username.toUpperCase()}) - DAY READINGS ===',
          opId: op.id,
          code: op.username.toLowerCase().replaceAll(' ', ''),
        ));
      }
    } else {
      for (final code in targetCodes) {
        sections.add((
          title: '=== ${code.toUpperCase()} DIVISION - DAY READINGS ===',
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
            tableTitle: '=== SPONGE IRON POLLUTION / DEDUSTING (${op.fullName.toUpperCase()}) ===',
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
          tableTitle: '=== SPONGE IRON POLLUTION / DEDUSTING EQUIPMENT ===',
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
            tableTitle: '=== WATER METERS (${op.fullName.toUpperCase()}) ===',
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
          tableTitle: '=== SID WATER METERS ===',
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
          tableTitle: '=== RMD WATER METERS ===',
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
      if (col.type == _ColumnType.reading) {
        final rwd = deviceDayReadings[col.device.id]?[cycleDates.first];
        final vals = rwd != null ? ReadingCalculationUtils.parseValues(rwd.reading.readingValues) : null;
        final val = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
        initRow.add(_formatDoubleCell(val));
      } else {
        initRow.add(TextCellValue('-'));
      }
    }
    sheet.appendRow(initRow);

    // 2. Final Reading Row
    final finalRow = <CellValue?>[TextCellValue('Final Reading (01-$endDateStr)')];
    for (final col in colDefs) {
      if (col.type == _ColumnType.reading) {
        final rwd = deviceDayReadings[col.device.id]?[cycleDates.last];
        final vals = rwd != null ? ReadingCalculationUtils.parseValues(rwd.reading.readingValues) : null;
        final val = vals?[col.unit] ?? vals?[col.unit.toLowerCase()];
        finalRow.add(_formatDoubleCell(val));
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

enum _ColumnType { reading, diff, mf, consumption, pf }

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
