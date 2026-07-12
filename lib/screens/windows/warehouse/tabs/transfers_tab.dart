import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/sales_provider.dart'; // For SalesFilter enum
import '../../../../theme/app_theme.dart';
import '../widgets/location_badge.dart';

class TransferHistoryTab extends StatefulWidget {
  const TransferHistoryTab({super.key});

  @override
  State<TransferHistoryTab> createState() => TransferHistoryTabState();
}

class TransferHistoryTabState extends State<TransferHistoryTab> {
  String _searchQuery = '';
  int _limit = 30;

  @override
  Widget build(BuildContext context) {
    final wh = context.watch<WarehouseProvider>();

    var history = wh.transfers;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      history = history.where((t) =>
          t.medicineName.toLowerCase().contains(q) ||
          t.note.toLowerCase().contains(q) ||
          t.fromWarehouse.toLowerCase().contains(q) ||
          t.toWarehouse.toLowerCase().contains(q) ||
          (t.batchNo ?? '').toLowerCase().contains(q) ||
          t.transferredBy.toLowerCase().contains(q)).toList();
    }

    final locations = const {
      'bulkClinic': 'Clinic Bulk',
      'clinic': 'Clinic',
      'bulkStore': 'Store Bulk',
      'store': 'Store',
    };

    return Column(
      children: [
        // Header, presets and Date Filter
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardColor,
            border: Border(bottom: BorderSide(color: context.borderColor)),
          ),
          child: Row(
            children: [
              const Icon(Icons.compare_arrows, color: AppTheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Stock Transfer History',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('${history.length} records found',
                      style: TextStyle(color: context.textMutedColor)),
                ],
              ),
              const Spacer(),
              
              // Date Presets
              Container(
                decoration: BoxDecoration(
                  color: context.bgColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: wh.customStart == null ? context.textMutedColor : AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      icon: const Icon(Icons.calendar_month, size: 20),
                      label: Text(
                        wh.customStart == null 
                            ? 'All Time' 
                            : '${wh.customStart!.day}/${wh.customStart!.month}/${wh.customStart!.year} - ${wh.customEnd?.day ?? ''}/${wh.customEnd?.month ?? ''}/${wh.customEnd?.year ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: () async {
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: wh.customStart != null && wh.customEnd != null ? DateTimeRange(start: wh.customStart!, end: wh.customEnd!) : null,
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppTheme.primary,
                                  onPrimary: Colors.white,
                                  onSurface: Colors.black,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (range != null) {
                          wh.setFilter(SalesFilter.custom, range: range);
                          setState(() => _limit = 30);
                        }
                      },
                    ),
                    if (wh.customStart != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: AppTheme.danger,
                        tooltip: 'Clear Date Filter',
                        onPressed: () {
                          wh.setFilter(SalesFilter.allTime);
                          setState(() => _limit = 30);
                        },
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down, size: 20, color: AppTheme.primary),
                      tooltip: 'Date Presets',
                      onSelected: (value) {
                        if (value == 'today') {
                          wh.setFilter(SalesFilter.today);
                        } else if (value == 'yesterday') {
                          wh.setFilter(SalesFilter.yesterday);
                        } else if (value == 'this_week') {
                          wh.setFilter(SalesFilter.last7Days);
                        } else if (value == 'all_time') {
                          wh.setFilter(SalesFilter.allTime);
                        }
                        setState(() => _limit = 30);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'today', child: Text('Today')),
                        const PopupMenuItem(value: 'yesterday', child: Text('Yesterday')),
                        const PopupMenuItem(value: 'this_week', child: Text('This Week')),
                        const PopupMenuItem(value: 'all_time', child: Text('All Time')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Search Bar
              SizedBox(
                width: 280,
                child: TextField(
                  onChanged: (v) => setState(() {
                    _searchQuery = v;
                    _limit = 30;
                  }),
                  decoration: InputDecoration(
                    hintText: 'Search medicine, batch, note...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: context.bgColor.withValues(alpha: 0.5),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.compare_arrows_outlined, size: 64, color: context.textMutedColor),
                      const SizedBox(height: 24),
                      Text('No transfer records found', style: TextStyle(color: context.textMutedColor, fontSize: 16)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 300),
                          child: Container(
                            decoration: BoxDecoration(
                              color: context.cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.borderColor),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(context.bgColor.withValues(alpha: 0.5)),
                                headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                                dataRowMinHeight: 60,
                                dataRowMaxHeight: 60,
                                dividerThickness: 1,
                                columns: const [
                                  DataColumn(label: Text('Date & Time')),
                                  DataColumn(label: Text('Medicine Name')),
                                  DataColumn(label: Text('From Location')),
                                  DataColumn(label: Text('To Location')),
                                  DataColumn(label: Text('Batch Number')),
                                  DataColumn(label: Text('Qty'), numeric: true),
                                  DataColumn(label: Text('Notes')),
                                  DataColumn(label: Text('Transferred By')),
                                ],
                                rows: history.take(_limit).map((t) {
                                  final dateStr = '${t.transferredAt.day.toString().padLeft(2,'0')}/${t.transferredAt.month.toString().padLeft(2,'0')}/${t.transferredAt.year} ${t.transferredAt.hour.toString().padLeft(2,'0')}:${t.transferredAt.minute.toString().padLeft(2,'0')}';
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(dateStr, style: const TextStyle(fontSize: 13))),
                                      DataCell(Text(t.medicineName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                                      DataCell(LocationBadge(location: t.fromWarehouse)),
                                      DataCell(LocationBadge(location: t.toWarehouse)),
                                      DataCell(Text(t.batchNo ?? '-', style: TextStyle(fontSize: 13, color: t.batchNo == null ? context.textMutedColor : null))),
                                      DataCell(Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: AppTheme.primaryLight.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text('${t.qty}', style: const TextStyle(color: AppTheme.primaryLight, fontWeight: FontWeight.bold)),
                                      )),
                                      DataCell(SizedBox(
                                        width: 150,
                                        child: Text(t.note.isEmpty ? '-' : t.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.textMutedColor, fontStyle: FontStyle.italic)),
                                      )),
                                      DataCell(Text(t.transferredBy, style: const TextStyle(fontSize: 13))),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (history.length > _limit)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Center(
                            child: FilledButton.icon(
                              onPressed: () => setState(() => _limit += 30),
                              icon: const Icon(Icons.expand_more),
                              label: const Text('Load More'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
