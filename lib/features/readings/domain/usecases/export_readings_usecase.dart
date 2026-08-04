import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/app_date_utils.dart';
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
        dir = await getExternalStorageDirectory();
      } else {
        dir = await getDownloadsDirectory();
      }
      if (dir == null) return null;
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

      final row1 = <CellValue?>[
        TextCellValue('Date'),
        TextCellValue('Reading Time'),
        TextCellValue('Posted Time'),
        TextCellValue('Heat #'),
      ];

      final row2 = <CellValue?>[
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
      ];

      for (final d in devices) {
        row1.add(TextCellValue(d.name as String));
        row1.add(TextCellValue(''));
        row2.add(TextCellValue('KWH Consump'));
        row2.add(TextCellValue('KWHLT Consump'));
      }

      sheet.appendRow(row1);
      sheet.appendRow(row2);

      for (final rwd in readings) {
        final r = rwd.reading;
        final readingDt = DateTime.fromMillisecondsSinceEpoch(r.readingDate, isUtc: true).toLocal();
        final postedDt = DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true).toLocal();
        final dateStr = DateFormat('dd MMM yyyy').format(readingDt);
        final readingTimeStr = DateFormat('hh:mm a').format(readingDt);
        final postedTimeStr = DateFormat('hh:mm a').format(postedDt);

        final row = <CellValue?>[
          TextCellValue(dateStr),
          TextCellValue(readingTimeStr),
          TextCellValue(postedTimeStr),
          TextCellValue(r.heatNumber.isEmpty ? '-' : r.heatNumber),
        ];

        for (final d in devices) {
          final belongs = r.deviceId == d.id;
          if (belongs) {
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
          } else {
            row.add(TextCellValue('-'));
            row.add(TextCellValue('-'));
          }
        }
        sheet.appendRow(row);
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
}
