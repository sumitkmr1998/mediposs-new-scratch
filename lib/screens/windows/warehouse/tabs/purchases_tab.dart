import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/purchase_record.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';
import '../widgets/location_badge.dart';
import '../dialogs/edit_purchase_dialog.dart';

class PurchaseHistoryTab extends StatefulWidget {
  const PurchaseHistoryTab({super.key});

  @override
  State<PurchaseHistoryTab> createState() => PurchaseHistoryTabState();
}

class PurchaseHistoryTabState extends State<PurchaseHistoryTab> {
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  int _limit = 30;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    
    var history = inv.purchaseHistory;
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      history = history.where((p) => p.medicineName.toLowerCase().contains(q) || p.supplier.toLowerCase().contains(q)).toList();
    }
    
    // Apply date filter
    if (_startDate != null) {
      history = history.where((p) => p.purchasedAt.isAfter(_startDate!) || p.purchasedAt.isAtSameMomentAs(_startDate!)).toList();
    }
    if (_endDate != null) {
      // add 1 day to include the entire end date
      final end = _endDate!.add(const Duration(days: 1));
      history = history.where((p) => p.purchasedAt.isBefore(end)).toList();
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cardColor,
            border: Border(bottom: BorderSide(color: context.borderColor)),
          ),
          child: Row(
            children: [
              const Icon(Icons.history, color: AppTheme.primary),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Inventory Purchase History',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text('${history.length} records found',
                      style: TextStyle(color: context.textMutedColor)),
                ],
              ),
              const Spacer(),
              
              // Date Filter
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
                        foregroundColor: _startDate == null ? context.textMutedColor : AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      icon: const Icon(Icons.calendar_month, size: 20),
                      label: Text(
                        _startDate == null 
                            ? 'Filter by Date' 
                            : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - ${_endDate?.day ?? ''}/${_endDate?.month ?? ''}/${_endDate?.year ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _startDate != null && _endDate != null ? DateTimeRange(start: _startDate!, end: _endDate!) : null,
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
                        if (picked != null) {
                          setState(() {
                            _startDate = picked.start;
                            _endDate = picked.end;
                            _limit = 30;
                          });
                        }
                      },
                    ),
                    if (_startDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: AppTheme.danger,
                        tooltip: 'Clear Date Filter',
                        onPressed: () => setState(() {
                          _startDate = null;
                          _endDate = null;
                          _limit = 30;
                        }),
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down, size: 20, color: AppTheme.primary),
                      tooltip: 'Date Presets',
                      onSelected: (value) {
                        final now = DateTime.now();
                        setState(() {
                          if (value == 'today') {
                            _startDate = DateTime(now.year, now.month, now.day);
                            _endDate = _startDate;
                          } else if (value == 'yesterday') {
                            _startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
                            _endDate = _startDate;
                          } else if (value == 'this_week') {
                            _startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
                            _endDate = _startDate!.add(const Duration(days: 6));
                          } else if (value == 'this_month') {
                            _startDate = DateTime(now.year, now.month, 1);
                            _endDate = DateTime(now.year, now.month + 1, 0);
                          }
                          _limit = 30;
                        });
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'today', child: Text('Today')),
                        const PopupMenuItem(value: 'yesterday', child: Text('Yesterday')),
                        const PopupMenuItem(value: 'this_week', child: Text('This Week')),
                        const PopupMenuItem(value: 'this_month', child: Text('This Month')),
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
                    hintText: 'Search medicine or supplier...',
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
                      Icon(Icons.inventory_2_outlined, size: 64, color: context.textMutedColor),
                      const SizedBox(height: 24),
                      Text('No purchase records found', style: TextStyle(color: context.textMutedColor, fontSize: 16)),
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
                                  DataColumn(label: Text('Supplier')),
                                  DataColumn(label: Text('Purchase Price'), numeric: true),
                                  DataColumn(label: Text('Qty'), numeric: true),
                                  DataColumn(label: Text('Target Location')),
                                  DataColumn(label: Text('Notes')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: history.take(_limit).map((p) {
                                  final dateStr = '${p.purchasedAt.day.toString().padLeft(2,'0')}/${p.purchasedAt.month.toString().padLeft(2,'0')}/${p.purchasedAt.year} ${p.purchasedAt.hour.toString().padLeft(2,'0')}:${p.purchasedAt.minute.toString().padLeft(2,'0')}';
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(dateStr, style: const TextStyle(fontSize: 13))),
                                      DataCell(Text(p.medicineName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                                      DataCell(
                                        p.supplier.isEmpty 
                                            ? Text('-', style: TextStyle(color: context.textMutedColor))
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.business, size: 14, color: context.textMutedColor),
                                                  const SizedBox(width: 6),
                                                  Text(p.supplier, style: const TextStyle(fontWeight: FontWeight.w600)),
                                                ],
                                              )
                                      ),
                                      DataCell(Text('₹${p.purchasePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.success))),
                                      DataCell(Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: AppTheme.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                        child: Text('+${p.qty}', style: const TextStyle(color: AppTheme.indigo, fontWeight: FontWeight.bold)),
                                      )),
                                      DataCell(LocationBadge(location: p.location)),
                                      DataCell(SizedBox(
                                        width: 150,
                                        child: Text(p.note.isEmpty ? '-' : p.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.textMutedColor, fontStyle: FontStyle.italic)),
                                      )),
                                      DataCell(Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            color: AppTheme.primary,
                                            tooltip: 'Edit Record',
                                            onPressed: () => showDialog(context: context, builder: (ctx) => EditPurchaseDialog(purchase: p)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 18),
                                            color: AppTheme.danger,
                                            tooltip: 'Delete Record',
                                            onPressed: () => _showDeleteConfirm(context, inv, p),
                                          ),
                                        ],
                                      )),
                                    ]
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

  void _showDeleteConfirm(
      BuildContext context, InventoryProvider inv, PurchaseRecord p) {
    final loc = p.location;
    final locationName = loc == 'store' ? 'Store POS' :
                         loc == 'bulkClinic' ? 'Bulk Clinic' :
                         loc == 'bulkStore' ? 'Bulk Store' :
                         loc == 'clinic' ? 'Clinic Dispense' : 'Hub/Clinic';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Purchase Record?'),
        content: Text(
            'This will also deduct ${p.qty} from the $locationName stock for ${p.medicineName}. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              final actor = context.read<AuthProvider>().currentUser;
              inv.deletePurchase(p, syncService: context.read<SyncService>(), actor: actor);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Record deleted and stock reverted'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
              ));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
