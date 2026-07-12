import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../../../shared/models/schedule_h1_record.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/objectbox_service.dart';
import '../../../../objectbox.g.dart';
import '../../../../theme/app_theme.dart';

class ScheduleH1RegisterTab extends StatefulWidget {
  const ScheduleH1RegisterTab({super.key});

  @override
  State<ScheduleH1RegisterTab> createState() => _ScheduleH1RegisterTabState();
}

class _ScheduleH1RegisterTabState extends State<ScheduleH1RegisterTab> {
  String _h1SearchQuery = '';
  String _h1Period = 'This Month';
  DateTimeRange? _h1CustomRange;

  Widget _buildPeriodSelector({
    required String selectedPeriod,
    required List<String> periods,
    required ValueChanged<String> onPeriodSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: periods.map((p) {
          final isSelected = p == selectedPeriod;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onPeriodSelected(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  p,
                  style: TextStyle(
                    color: isSelected ? Colors.white : context.textColor.withValues(alpha: 0.8),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _exportH1ToExcel(List<ScheduleH1Record> records) async {
    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Schedule H1 Register'];
      excel.delete('Sheet1');

      sheet.appendRow([
        excel_pkg.TextCellValue('Date & Time'),
        excel_pkg.TextCellValue('Invoice No'),
        excel_pkg.TextCellValue('Drug Name'),
        excel_pkg.TextCellValue('Batch No'),
        excel_pkg.TextCellValue('Quantity'),
        excel_pkg.TextCellValue('Patient Name'),
        excel_pkg.TextCellValue('Patient Address'),
        excel_pkg.TextCellValue('Patient Phone'),
        excel_pkg.TextCellValue('Doctor Name'),
        excel_pkg.TextCellValue('Doctor Address'),
        excel_pkg.TextCellValue('Doctor Reg No'),
      ]);

      for (final r in records) {
        sheet.appendRow([
          excel_pkg.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(r.saleDate)),
          excel_pkg.TextCellValue(r.invoiceNo),
          excel_pkg.TextCellValue(r.medicineName),
          excel_pkg.TextCellValue(r.batchNo),
          excel_pkg.IntCellValue(r.quantity),
          excel_pkg.TextCellValue(r.patientName),
          excel_pkg.TextCellValue(r.patientAddress),
          excel_pkg.TextCellValue(r.patientPhone),
          excel_pkg.TextCellValue(r.doctorName),
          excel_pkg.TextCellValue(r.doctorAddress),
          excel_pkg.TextCellValue(r.doctorRegistrationNo),
        ]);
      }

      final dir = await getApplicationDocumentsDirectory();
      final dateStr = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final file = File(p.join(dir.path, 'Schedule_H1_Register_$dateStr.xlsx'));
      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Register exported successfully to: ${file.path}'),
              backgroundColor: AppTheme.success,
              action: SnackBarAction(
                label: 'Open Folder',
                textColor: Colors.white,
                onPressed: () {
                  final uri = Uri.directory(dir.path);
                  launchUrl(uri);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export register: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isStaffOnly = !authProvider.isAdmin;

    final h1Box = ObjectBoxService.instance.store.box<ScheduleH1Record>();
    
    final now = DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    if (isStaffOnly) {
      start = DateTime(now.year, now.month, now.day);
    } else if (_h1Period == 'Today') {
      start = DateTime(now.year, now.month, now.day);
    } else if (_h1Period == 'Yesterday') {
      final yest = now.subtract(const Duration(days: 1));
      start = DateTime(yest.year, yest.month, yest.day);
      end = DateTime(yest.year, yest.month, yest.day, 23, 59, 59);
    } else if (_h1Period == 'This Week') {
      start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    } else if (_h1Period == 'This Month') {
      start = DateTime(now.year, now.month, 1);
    } else if (_h1Period == 'Custom Range' && _h1CustomRange != null) {
      start = _h1CustomRange!.start;
      end = DateTime(_h1CustomRange!.end.year, _h1CustomRange!.end.month, _h1CustomRange!.end.day, 23, 59, 59);
    } else {
      start = DateTime(now.year, now.month, 1);
    }

    final queryBuilder = h1Box.query(
      ScheduleH1Record_.saleDate.between(
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ),
    );
    final query = queryBuilder.build();
    final allRecords = query.find();
    query.close();

    allRecords.sort((a, b) => b.saleDate.compareTo(a.saleDate));

    final filteredRecords = allRecords.where((r) {
      if (_h1SearchQuery.isEmpty) return true;
      final queryStr = _h1SearchQuery.toLowerCase();
      return r.medicineName.toLowerCase().contains(queryStr) ||
          r.patientName.toLowerCase().contains(queryStr) ||
          r.doctorName.toLowerCase().contains(queryStr) ||
          r.invoiceNo.toLowerCase().contains(queryStr);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Schedule H1 Register',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export Register to Excel'),
                onPressed: filteredRecords.isEmpty
                    ? null
                    : () => _exportH1ToExcel(filteredRecords),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by medicine, patient, doctor, or invoice...',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _h1SearchQuery = val;
                    });
                  },
                ),
              ),
              if (!isStaffOnly) ...[
                const SizedBox(width: 16),
                _buildPeriodSelector(
                  selectedPeriod: _h1Period,
                  periods: const ['Today', 'Yesterday', 'This Week', 'This Month', 'Custom Range'],
                  onPeriodSelected: (p) async {
                    if (p == 'Custom Range') {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: _h1CustomRange,
                      );
                      if (range != null) {
                        setState(() {
                          _h1Period = p;
                          _h1CustomRange = range;
                        });
                      }
                    } else {
                      setState(() {
                        _h1Period = p;
                        _h1CustomRange = null;
                      });
                    }
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 2, child: Text('Date & Invoice', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 3, child: Text('Drug Name & Batch', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 1, child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 3, child: Text('Patient Name & Address', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 3, child: Text('Doctor Name & Address (Reg No)', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filteredRecords.isEmpty
                          ? const Center(child: Text('No compliance logs found for the selected period.'))
                          : ListView.separated(
                              itemCount: filteredRecords.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final r = filteredRecords[index];
                                final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(r.saleDate);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            Text(r.invoiceNo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.medicineName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('Batch: ${r.batchNo}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text('${r.quantity}'),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text(r.patientAddress, style: const TextStyle(fontSize: 11)),
                                            if (r.patientPhone.isNotEmpty)
                                              Text('Ph: ${r.patientPhone}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Dr. ${r.doctorName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text(r.doctorAddress, style: const TextStyle(fontSize: 11)),
                                            if (r.doctorRegistrationNo.isNotEmpty)
                                              Text('Reg: ${r.doctorRegistrationNo}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
