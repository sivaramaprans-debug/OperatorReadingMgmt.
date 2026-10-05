import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../../../../database/supabase_providers.dart';
import '../../domain/usecases/export_readings_usecase.dart';

class MonthlyReportDialog extends ConsumerStatefulWidget {
  const MonthlyReportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const MonthlyReportDialog(),
    );
  }

  @override
  ConsumerState<MonthlyReportDialog> createState() => _MonthlyReportDialogState();
}

class _MonthlyReportDialogState extends ConsumerState<MonthlyReportDialog> {
  bool _isFinancialYear = true;
  late int _selectedFyStartYear;
  late int _selectedYear;
  late int _selectedMonth;
  bool _isExporting = false;
  String? _statusMessage;

  final List<int> _years = [
    DateTime.now().year - 2,
    DateTime.now().year - 1,
    DateTime.now().year,
    DateTime.now().year + 1,
  ];

  final List<int> _fyStartYears = [
    DateTime.now().year - 2,
    DateTime.now().year - 1,
    DateTime.now().year,
  ];

  final List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _selectedFyStartYear = now.month >= 4 ? now.year : now.year - 1;
    if (!_fyStartYears.contains(_selectedFyStartYear)) {
      _fyStartYears.add(_selectedFyStartYear);
      _fyStartYears.sort();
    }
  }

  DateTime get _startDate => DateTime(_selectedYear, _selectedMonth, 1);
  DateTime get _endDate => DateTime(_selectedYear, _selectedMonth + 1, 1);

  String get _cycleText {
    if (_isFinancialYear) {
      final nextYearShort = (_selectedFyStartYear + 1).toString().substring(2);
      return 'FY $_selectedFyStartYear-$nextYearShort (01-Apr-$_selectedFyStartYear to 01-Apr-${_selectedFyStartYear + 1} - 12 Months)';
    }
    final start = DateFormat('01-MMM-yyyy').format(_startDate);
    final end = DateFormat('01-MMM-yyyy').format(_endDate);
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    return '$start to $end (${daysInMonth + 1} daily records)';
  }

  Future<void> _handleExport() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Querying Supabase data & preparing sheets...';
    });

    try {
      final usecase = ExportReadingsUseCase();
      final devicesRepo = ref.read(supabaseDevicesRepoProvider);
      final operatorsRepo = ref.read(supabaseOperatorsRepoProvider);
      final readingsRepo = ref.read(supabaseReadingsRepoProvider);
      final replacementsRepo = ref.read(supabaseMeterReplacementRepoProvider);

      final filePath = _isFinancialYear
          ? await usecase.generateAndExportFinancialYearStatement(
              fyStartYear: _selectedFyStartYear,
              devicesRepo: devicesRepo,
              operatorsRepo: operatorsRepo,
              readingsRepo: readingsRepo,
              replacementsRepo: replacementsRepo,
            )
          : await usecase.generateAndExportMonthlyReport(
              year: _selectedYear,
              month: _selectedMonth,
              devicesRepo: devicesRepo,
              operatorsRepo: operatorsRepo,
              readingsRepo: readingsRepo,
              replacementsRepo: replacementsRepo,
            );

      if (!mounted) return;

      if (filePath != null) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_isFinancialYear ? "Financial Year" : "Monthly"} report saved:\n$filePath'),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'OPEN FILE',
              textColor: Colors.amberAccent,
              onPressed: () async {
                try {
                  await OpenFilex.open(filePath);
                } catch (_) {}
              },
            ),
          ),
        );
      } else {
        setState(() {
          _isExporting = false;
          _statusMessage = 'Export failed or was cancelled. Please check storage permissions.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _statusMessage = 'Error during export: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.calendar_month_rounded, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Export Plant Report',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Generates a comprehensive 4-sheet plant report (Energy Abstract, SMS Divisions, SID Dedusting, Water Meters).',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            // Report Type Selector
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Financial Year (12 Mo)')),
                    selected: _isFinancialYear,
                    onSelected: _isExporting ? null : (selected) {
                      if (selected) setState(() => _isFinancialYear = true);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Single Month')),
                    selected: !_isFinancialYear,
                    onSelected: _isExporting ? null : (selected) {
                      if (selected) setState(() => _isFinancialYear = false);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_isFinancialYear) ...[
              DropdownButtonFormField<int>(
                value: _selectedFyStartYear,
                decoration: const InputDecoration(
                  labelText: 'Financial Year',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _fyStartYears.map((fy) {
                  final nextShort = (fy + 1).toString().substring(2);
                  return DropdownMenuItem<int>(
                    value: fy,
                    child: Text('FY $fy-$nextShort (01-Apr-$fy to 01-Apr-${fy + 1})'),
                  );
                }).toList(),
                onChanged: _isExporting
                    ? null
                    : (val) {
                        if (val != null) setState(() => _selectedFyStartYear = val);
                      },
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      value: _selectedMonth,
                      decoration: const InputDecoration(
                        labelText: 'Month',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: List.generate(12, (index) {
                        final m = index + 1;
                        return DropdownMenuItem<int>(
                          value: m,
                          child: Text(_monthNames[index]),
                        );
                      }),
                      onChanged: _isExporting
                          ? null
                          : (val) {
                              if (val != null) setState(() => _selectedMonth = val);
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: _selectedYear,
                      decoration: const InputDecoration(
                        labelText: 'Year',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _years.map((y) {
                        return DropdownMenuItem<int>(
                          value: y,
                          child: Text(y.toString()),
                        );
                      }).toList(),
                      onChanged: _isExporting
                          ? null
                          : (val) {
                              if (val != null) setState(() => _selectedYear = val);
                            },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.date_range_rounded, size: 16, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Text(
                        'Billing Cycle:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _cycleText,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Sheets included in workbook (.xlsx):',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 6),
            _sheetBadge(
              icon: Icons.electric_bolt_rounded,
              color: Colors.amber.shade800,
              name: '1. Energy_Abstract',
              desc: 'Day readings of plant energy meters (no heat/water/pollution)',
            ),
            _sheetBadge(
              icon: Icons.factory_rounded,
              color: Colors.deepOrange.shade700,
              name: '2. SMS_Divisions',
              desc: 'SMS 2, SMS 3, SMS 4 separate tables on one sheet',
            ),
            _sheetBadge(
              icon: Icons.air_rounded,
              color: Colors.teal.shade700,
              name: '3. SID_Dedusting',
              desc: 'Sponge Iron pollution control equipment by operator',
            ),
            _sheetBadge(
              icon: Icons.water_drop_rounded,
              color: Colors.blue.shade700,
              name: '4. Water_Meters',
              desc: 'SID & RMD water meters with separate operator tables',
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: _isExporting ? theme.colorScheme.primary : Colors.red.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (_isExporting) ...[
              const SizedBox(height: 12),
              const Center(child: LinearProgressIndicator()),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.file_download_rounded, size: 18),
          label: Text(_isExporting ? 'Exporting...' : 'Export Excel'),
          onPressed: _isExporting ? null : _handleExport,
        ),
      ],
    );
  }

  Widget _sheetBadge({
    required IconData icon,
    required Color color,
    required String name,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                children: [
                  TextSpan(text: '$name: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: desc, style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
