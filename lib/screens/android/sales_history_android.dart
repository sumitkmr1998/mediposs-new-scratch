import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/sale.dart';
import '../../theme/app_theme.dart';
import '../../widgets/return_dialog.dart';
import '../../shared/services/printing_service.dart';

class SalesHistoryAndroid extends StatefulWidget {
  const SalesHistoryAndroid({super.key});

  @override
  State<SalesHistoryAndroid> createState() => _SalesHistoryAndroidState();
}

class _SalesHistoryAndroidState extends State<SalesHistoryAndroid> {
  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
      ),
      body: Column(
        children: [
          // Summary banner
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primary.withValues(alpha: 0.1),
            child: LayoutBuilder(builder: (ctx, constraints) {
              final rangeLabel = _getRangeLabel(sales);

              // Local calculations for filtered list
              double grossSales = 0;
              double returns = 0;
              for (final s in sales.sales) {
                if (s.isReturn) {
                  returns += s.total.abs();
                } else {
                  grossSales += s.total;
                }
              }
              final netTotal = grossSales - returns;

              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatBadge(
                          label: "Gross Sales",
                          value: '₹${grossSales.toStringAsFixed(0)}',
                          color: AppTheme.primary),
                      _StatBadge(
                          label: "Returns",
                          value: '₹${returns.toStringAsFixed(0)}',
                          color: AppTheme.danger),
                      _StatBadge(
                          label: "Net Total",
                          value: '₹${netTotal.toStringAsFixed(0)}',
                          color: AppTheme.success),
                    ],
                  ),
                  const Divider(height: 24, thickness: 0.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatBadge(
                          label: "$rangeLabel Sales",
                          value:
                              '${sales.sales.where((s) => !s.isReturn).length}',
                          color: AppTheme.primaryLight),
                      _StatBadge(
                          label: "$rangeLabel Returns",
                          value:
                              '${sales.sales.where((s) => s.isReturn).length}',
                          color: AppTheme.danger),
                      _StatBadge(
                          label: 'All-time Revenue',
                          value: '₹${sales.totalRevenue.toStringAsFixed(0)}',
                          color: AppTheme.accent),
                    ],
                  ),
                ],
              );
            }),
          ),

          // Date Filter Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Today',
                  isSelected: sales.activeFilter == SalesFilter.today,
                  onSelected: () => sales.setFilter(SalesFilter.today),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Yesterday',
                  isSelected: sales.activeFilter == SalesFilter.yesterday,
                  onSelected: () => sales.setFilter(SalesFilter.yesterday),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Last 7 Days',
                  isSelected: sales.activeFilter == SalesFilter.last7Days,
                  onSelected: () => sales.setFilter(SalesFilter.last7Days),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'All Time',
                  isSelected: sales.activeFilter == SalesFilter.allTime,
                  onSelected: () => sales.setFilter(SalesFilter.allTime),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Custom',
                  isSelected: sales.activeFilter == SalesFilter.custom,
                  onSelected: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (ctx, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: Theme.of(context).colorScheme.copyWith(
                                  primary: AppTheme.primary,
                                  onPrimary: Colors.white,
                                ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (range != null) {
                      sales.setFilter(SalesFilter.custom, range: range);
                    }
                  },
                ),
              ],
            ),
          ),

          // Sales list
          Expanded(
            child: sales.sales.isEmpty
                ? Center(
                    child: Text('No sales yet',
                        style: TextStyle(color: context.textMutedColor)))
                : ListView.builder(
                    itemCount: sales.sales.length,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemBuilder: (ctx, i) =>
                        _SaleRow(sale: sales.sales[i], salesProvider: sales),
                  ),
          ),
        ],
      ),
    );
  }

  String _getRangeLabel(SalesProvider sales) {
    switch (sales.activeFilter) {
      case SalesFilter.today:
        return "Today's";
      case SalesFilter.yesterday:
        return "Yesterday's";
      case SalesFilter.last7Days:
        return "7 Days'";
      case SalesFilter.allTime:
        return "All-time";
      case SalesFilter.custom:
        return "Custom";
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : context.textMutedColor,
          )),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primary,
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : context.borderColor,
        ),
      ),
      showCheckmark: false,
    );
  }
}

class _SaleRow extends StatelessWidget {
  final Sale sale;
  final SalesProvider salesProvider;

  const _SaleRow({required this.sale, required this.salesProvider});

  @override
  Widget build(BuildContext context) {
    final dt = sale.createdAt;
    final canVoidSales = context.watch<AuthProvider>().canVoidSales;
    final canProcessReturns = context.watch<AuthProvider>().canProcessReturns;
    final inv = context.read<InventoryProvider>();

    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: context.borderColor),
        ),
        elevation: 0,
        color: context.surfaceColor,
        child: ExpansionTile(
          shape: const Border(),
          leading: CircleAvatar(
            backgroundColor: sale.isReturn
                ? AppTheme.danger.withValues(alpha: 0.1)
                : AppTheme.primaryLight.withValues(alpha: 0.1),
            child: Icon(
              sale.isReturn ? Icons.assignment_return : Icons.receipt,
              color: sale.isReturn ? AppTheme.danger : AppTheme.primaryLight,
              size: 20,
            ),
          ),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  sale.patientName.isEmpty ? 'Walk-in' : sale.patientName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '₹${sale.total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: sale.isReturn ? AppTheme.danger : AppTheme.success,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    sale.invoiceNo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${dt.day}/${dt.month}/${dt.year}',
                    style:
                        TextStyle(fontSize: 12, color: context.textMutedColor),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (sale.isReturn)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('REFUND',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.danger)),
                    ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      sale.paymentMethod.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10, color: context.textMutedColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...salesProvider.getSaleItems(sale).map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text(item.medicineName)),
                            Text(
                                '${item.qty} × ₹${item.unitPrice.toStringAsFixed(2)}'),
                            const SizedBox(width: 16),
                            Text('₹${item.lineTotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )),
                  const Divider(),
                  if (sale.discount > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('Discount: -₹${sale.discount.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.danger)),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Total: ₹${sale.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryLight,
                              fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          PrintingService.instance.printReceipt(context, sale);
                        },
                        icon: const Icon(Icons.print,
                            color: AppTheme.primaryLight, size: 18),
                        label: const Text('Print Receipt',
                            style: TextStyle(color: AppTheme.primaryLight)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primaryLight),
                        ),
                      ),
                      if (!sale.isReturn && canProcessReturns) ...[
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => ReturnDialog(originalSale: sale),
                            );
                          },
                          icon: const Icon(Icons.assignment_return,
                              color: AppTheme.danger, size: 18),
                          label: const Text('Process Return',
                              style: TextStyle(color: AppTheme.danger)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.danger),
                          ),
                        ),
                      ],
                      if (canVoidSales) ...[
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () => _confirmDelete(context, inv),
                          icon: const Icon(Icons.delete_forever,
                              color: AppTheme.danger, size: 18),
                          label: const Text('Void Sale',
                              style: TextStyle(color: AppTheme.danger)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.danger),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ));
  }

  void _confirmDelete(BuildContext context, InventoryProvider inv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            const Text('Void Sale', style: TextStyle(color: AppTheme.danger)),
        content: Text(
            'Are you sure you want to permanently delete receipt ${sale.invoiceNo}?\n\nThis will precisely refund all inventory quantities and completely remove this record from the sales ledger.'),
        backgroundColor: context.surfaceColor,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: context.textMutedColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            onPressed: () {
              salesProvider.deleteSale(sale, inv);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sale ${sale.invoiceNo} voided successfully.'),
                  backgroundColor: AppTheme.success,
                ),
              );
            },
            child: const Text('Yes, Void Sale'),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBadge(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: context.textMutedColor)),
      ],
    );
  }
}
