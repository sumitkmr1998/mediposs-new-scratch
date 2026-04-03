import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/sale.dart';
import '../../theme/app_theme.dart';
import '../../widgets/return_dialog.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_filter_chip.dart';

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
        title: const Text('Verified Audit Log'),
      ),
      body: Column(
        children: [
          // 1. High-Density Financial Summary (Glassmorphic)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(
                  bottom: BorderSide(
                      color: context.borderColor.withValues(alpha: 0.5))),
            ),
            child: LayoutBuilder(builder: (ctx, constraints) {
              double grossSales = 0;
              double returns = 0;
              for (final s in sales.sales) {
                if (s.isReturn)
                  returns += s.total.abs();
                else
                  grossSales += s.total;
              }
              final netTotal = grossSales - returns;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('REVENUE COMPOSITION',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: context.textMutedColor,
                              letterSpacing: 1.5)),
                      const Spacer(),
                      const Icon(Icons.verified_user,
                          size: 12, color: AppTheme.success),
                      const SizedBox(width: 4),
                      Text('SENTRY PROTECTION ACTIVE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.success.withValues(alpha: 0.8))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: "GROSS",
                          value: '₹${grossSales.toStringAsFixed(0)}',
                          color: AppTheme.primary,
                          icon: Icons.trending_up_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: "RETURNS",
                          value: '₹${returns.toStringAsFixed(0)}',
                          color: AppTheme.danger,
                          icon: Icons.assignment_return_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          label: "NET INCOME",
                          value: '₹${netTotal.toStringAsFixed(0)}',
                          color: AppTheme.success,
                          icon: Icons.account_balance_wallet_rounded,
                          isProminent: true,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ),

          // 2. Filter Bar
          Container(
            color: context.surfaceColor,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AppFilterChip(
                    label: 'Today',
                    isSelected: sales.activeFilter == SalesFilter.today,
                    onTap: () => sales.setFilter(SalesFilter.today),
                    style: AppFilterChipStyle.filled,
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Yesterday',
                    isSelected: sales.activeFilter == SalesFilter.yesterday,
                    onTap: () => sales.setFilter(SalesFilter.yesterday),
                    style: AppFilterChipStyle.filled,
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Last 7 Days',
                    isSelected: sales.activeFilter == SalesFilter.last7Days,
                    onTap: () => sales.setFilter(SalesFilter.last7Days),
                    style: AppFilterChipStyle.filled,
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'History',
                    isSelected: sales.activeFilter == SalesFilter.allTime,
                    onTap: () => sales.setFilter(SalesFilter.allTime),
                    style: AppFilterChipStyle.filled,
                  ),
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: 'Range',
                    isSelected: sales.activeFilter == SalesFilter.custom,
                    onTap: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (range != null) {
                        sales.setFilter(SalesFilter.custom, range: range);
                      }
                    },
                    style: AppFilterChipStyle.filled,
                  ),
                ],
              ),
            ),
          ),

          // 3. Verified Stream Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                Text('TRANSACTION STREAM',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: context.textMutedColor,
                        letterSpacing: 1)),
                const Spacer(),
                Text('${sales.sales.length} LOGS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.textMutedColor)),
              ],
            ),
          ),

          // list
          Expanded(
            child: sales.sales.isEmpty
                ? const AppEmptyState(
                    icon: Icons.history_rounded,
                    title: 'No verified logs found',
                  )
                : ListView.builder(
                    itemCount: sales.sales.length,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                    itemBuilder: (ctx, i) =>
                        _SaleRow(sale: sales.sales[i], salesProvider: sales),
                  ),
          ),
        ],
      ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: const Border(),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: (sale.isReturn ? AppTheme.danger : AppTheme.primaryLight)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            sale.isReturn ? Icons.assignment_return : Icons.receipt_long,
            color: sale.isReturn ? AppTheme.danger : AppTheme.primaryLight,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                sale.patientName.isEmpty ? 'Walk-in Guest' : sale.patientName,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: -0.3),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '₹${sale.total.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: sale.isReturn ? AppTheme.danger : AppTheme.primaryLight,
                fontSize: 16,
              ),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              sale.invoiceNo,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: context.textMutedColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('VERIFIED',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success)),
            ),
            const Spacer(),
            Text(
              '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.textMutedColor),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LINE ITEMS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryLight)),
                const SizedBox(height: 12),
                ...salesProvider.getSaleItems(sale).map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.medicineName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                Text(
                                    '${item.qty} units @ ₹${item.unitPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: context.textMutedColor)),
                              ],
                            ),
                          ),
                          Text('₹${item.lineTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13)),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('PAYMENT VIA ${sale.paymentMethod.toUpperCase()}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: context.textMutedColor)),
                    if (sale.discount > 0)
                      Text('Disc: -₹${sale.discount.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          PrintingService.instance.printReceipt(context, sale);
                        },
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('PRINT'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryLight,
                          side: const BorderSide(color: AppTheme.primaryLight),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!sale.isReturn && canProcessReturns)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            showDialog(
                                context: context,
                                builder: (_) =>
                                    ReturnDialog(originalSale: sale));
                          },
                          icon: const Icon(Icons.assignment_return_rounded,
                              size: 18),
                          label: const Text('RETURN'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(color: AppTheme.danger),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    if (canVoidSales) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _confirmDelete(context, inv),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppTheme.danger),
                        tooltip: 'Void Sale',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, InventoryProvider inv) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void Transaction',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
            'Permanently remove ${sale.invoiceNo} and restore inventory stock?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            onPressed: () {
              salesProvider.deleteSale(sale, inv);
              Navigator.pop(ctx);
            },
            child: const Text('VOID SALE'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isProminent;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isProminent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isProminent ? color : color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: isProminent ? Colors.white : color),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: isProminent ? Colors.white : color,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isProminent
                      ? Colors.white.withValues(alpha: 0.8)
                      : context.textMutedColor,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}
