import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/medicine_dialog.dart';
import '../../../../shared/widgets/app_empty_state.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../shared/widgets/app_status_badge.dart';
import '../dialogs/batch_details_dialog.dart';

class StockReportTab extends StatefulWidget {
  const StockReportTab({super.key});

  @override
  State<StockReportTab> createState() => StockReportTabState();
}

class StockReportTabState extends State<StockReportTab> {
  String _search = '';
  String _sortBy = 'name'; // 'name', 'bulk', 'counter', 'total'
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final meds = inv.rawMedicines.where((m) {
      return m.name.toLowerCase().contains(_search.toLowerCase()) ||
          m.barcode.contains(_search);
    }).toList();

    // Sort medicines
    meds.sort((a, b) {
      int compare;
      if (_sortBy == 'bulk') {
        final bulkA = a.bulkClinicStock + a.bulkStoreStock;
        final bulkB = b.bulkClinicStock + b.bulkStoreStock;
        compare = bulkA.compareTo(bulkB);
      } else if (_sortBy == 'counter') {
        final counterA = a.mainStock + a.storeStock;
        final counterB = b.mainStock + b.storeStock;
        compare = counterA.compareTo(counterB);
      } else if (_sortBy == 'total') {
        compare = a.totalStock.compareTo(b.totalStock);
      } else {
        compare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? compare : -compare;
    });

    return Column(
      children: [
        // Search & Filter Header
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            border: Border(
                bottom: BorderSide(
                    color: context.borderColor.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search medicine...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: context.bgColor.withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _sortBy,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'name', child: Text('Sort by Name')),
                  DropdownMenuItem(value: 'bulk', child: Text('Sort by Bulk Stock')),
                  DropdownMenuItem(value: 'counter', child: Text('Sort by Counter Stock')),
                  DropdownMenuItem(value: 'total', child: Text('Sort by Total Stock')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      if (_sortBy == v) {
                        _sortAscending = !_sortAscending;
                      } else {
                        _sortBy = v;
                        _sortAscending = true;
                      }
                    });
                  }
                },
              ),
              IconButton(
                icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                onPressed: () => setState(() => _sortAscending = !_sortAscending),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: meds.isEmpty
              ? const AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No medicines found',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: meds.length,
                  itemBuilder: (ctx, i) {
                    final m = meds[i];
                    final bulkTotal = m.bulkClinicStock + m.bulkStoreStock;
                    final counterTotal = m.mainStock + m.storeStock;
                    
                    return StockReportRow(
                      medicine: m,
                      bulkTotal: bulkTotal,
                      counterTotal: counterTotal,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class StockReportRow extends StatefulWidget {
  final Medicine medicine;
  final int bulkTotal;
  final int counterTotal;

  const StockReportRow({
    super.key,
    required this.medicine,
    required this.bulkTotal,
    required this.counterTotal,
  });

  @override
  State<StockReportRow> createState() => StockReportRowState();
}

class StockReportRowState extends State<StockReportRow> {
  bool _isHovered = false;

  void _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    Medicine m,
    WarehouseProvider wh,
    AuthProvider auth,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.edit, color: AppTheme.primary),
            title: Text('Edit Medicine'),
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              MedicineDialog.show(context, medicine: m);
            });
          },
        ),
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.info_outline, color: AppTheme.primary),
            title: Text('Batch Details'),
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              showDialog(
                context: context,
                builder: (_) => BatchDetailsDialog(
                  medicine: m,
                  wh: wh,
                  canTransfer: auth.hasWarehouseWriteAccess,
                ),
              );
            });
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.medicine;
    final wh = context.read<WarehouseProvider>();
    final auth = context.watch<AuthProvider>();
    final sales = context.watch<SalesProvider>().rawSales;
    final velocity = AnalyticsHelper.dailyConsumptionRate(m.id, sales, trendDays: 30);
    final daysLeft = AnalyticsHelper.daysOfStockRemaining(m, sales, trendDays: 30);
    final inv = context.watch<InventoryProvider>();
    final isSmartLow = inv.isSmartLowStock(m, sales);

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details, m, wh, auth);
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? AppTheme.primary.withValues(alpha: 0.04)
                : context.surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? AppTheme.primary.withValues(alpha: 0.3)
                  : context.borderColor.withValues(alpha: 0.5),
              width: _isHovered ? 1.5 : 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : [],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.vaccines, color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      m.category.isEmpty ? 'General' : m.category,
                      style: TextStyle(color: context.textMutedColor, fontSize: 11),
                    ),
                    if (m.batches.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: m.batches.map((b) {
                          final bNo = b.batchNo ?? 'No Batch';
                          final totalBatchStock = b.mainStock + b.storeStock + b.bulkClinicStock + b.bulkStoreStock;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.borderColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$bNo (Exp: ${b.expiryDate.day}/${b.expiryDate.month}/${b.expiryDate.year}) ($totalBatchStock)',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: context.textColor.withValues(alpha: 0.8),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        'No Batches',
                        style: TextStyle(
                          fontSize: 9,
                          fontStyle: FontStyle.italic,
                          color: context.textMutedColor,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Bulk Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'BULK STOCK',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: context.textMutedColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.bulkTotal} ${m.unit}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.deepPurple,
                      ),
                    ),
                    Text(
                      'Store: ${m.bulkStoreStock} | Clinic: ${m.bulkClinicStock}',
                      style: TextStyle(fontSize: 9, color: context.textMutedColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Counter Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'COUNTER STOCK',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: context.textMutedColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.counterTotal} ${m.unit}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF14B8A6),
                      ),
                    ),
                    Text(
                      'Store: ${m.storeStock} | Clinic: ${m.mainStock}',
                      style: TextStyle(fontSize: 9, color: context.textMutedColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Total Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'TOTAL STOCK',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: context.textMutedColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${m.totalStock} ${m.unit}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: context.textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (m.totalStock <= 0)
                      AppStatusBadge(
                          label: 'OUT OF STOCK',
                          color: AppTheme.danger,
                          style: AppStatusBadgeStyle.text)
                    else if (velocity > 0 && daysLeft < 7)
                      AppStatusBadge(
                          label: 'CRITICAL',
                          color: AppTheme.danger,
                          style: AppStatusBadgeStyle.text)
                    else if (velocity > 0 && daysLeft < 15)
                      AppStatusBadge(
                          label: 'URGENT',
                          color: AppTheme.orange,
                          style: AppStatusBadgeStyle.text)
                    else if (velocity > 0 && daysLeft < 30)
                      AppStatusBadge(
                          label: 'DEPLETING',
                          color: AppTheme.warning,
                          style: AppStatusBadgeStyle.text)
                    else if (isSmartLow)
                      AppStatusBadge(
                          label: 'LOW STOCK',
                          color: AppTheme.warning,
                          style: AppStatusBadgeStyle.text),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
