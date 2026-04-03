import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/models/sale.dart';
import '../../theme/app_theme.dart';
import '../../widgets/return_dialog.dart';
import '../../shared/services/printing_service.dart';

class SalesHistoryWindows extends StatefulWidget {
  const SalesHistoryWindows({super.key});

  @override
  State<SalesHistoryWindows> createState() => _SalesHistoryWindowsState();
}

class _SalesHistoryWindowsState extends State<SalesHistoryWindows> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Sale> _filteredSales(List<Sale> sales) {
    if (_searchQuery.isEmpty) return sales;
    final q = _searchQuery.toLowerCase();
    return sales.where((s) {
      return s.invoiceNo.toLowerCase().contains(q) ||
          (s.patientName.isNotEmpty &&
              s.patientName.toLowerCase().contains(q)) ||
          s.paymentMethod.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    final displayed = _filteredSales(sales.displayedSales);

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
    final saleCount = sales.sales.where((s) => !s.isReturn).length;
    final returnCount = sales.sales.where((s) => s.isReturn).length;
    final rangeLabel = _getRangeLabel(sales);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: AppTheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sales History',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                Text('$rangeLabel overview',
                    style:
                        TextStyle(fontSize: 12, color: context.textMutedColor)),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Advanced Analytics Row
            LayoutBuilder(builder: (ctx, constraints) {
              final cols = constraints.maxWidth > 1200
                  ? 4
                  : (constraints.maxWidth > 800 ? 2 : 1);
              const spacing = 16.0;
              final cardWidth =
                  (constraints.maxWidth - (cols - 1) * spacing) / cols;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ANALYTICS OVERVIEW',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: context.textMutedColor)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      _GlassKpiCard(
                        label: 'Gross Sales',
                        value: '₹${grossSales.toStringAsFixed(0)}',
                        icon: Icons.trending_up_rounded,
                        color: AppTheme.primary,
                        count: '$saleCount transactions',
                        width: cardWidth,
                      ),
                      _GlassKpiCard(
                        label: 'Refunds',
                        value: '₹${returns.toStringAsFixed(0)}',
                        icon: Icons.keyboard_return_rounded,
                        color: AppTheme.danger,
                        count: '$returnCount entries',
                        width: cardWidth,
                      ),
                      _GlassKpiCard(
                        label: 'Net Revenue',
                        value: '₹${netTotal.toStringAsFixed(0)}',
                        icon: Icons.account_balance_wallet_rounded,
                        color: AppTheme.success,
                        count: '$rangeLabel performance',
                        width: cardWidth,
                      ),
                      _GlassKpiCard(
                        label: 'Total Collected',
                        value: '₹${sales.totalRevenue.toStringAsFixed(0)}',
                        icon: Icons.auto_graph_rounded,
                        color: AppTheme.accent,
                        count: 'Lifetime summary',
                        width: cardWidth,
                      ),
                    ],
                  ),
                ],
              );
            }),

            const SizedBox(height: 24),

            // Filter + Search Bar Area
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  _buildQuickFilters(sales),
                  const Spacer(),
                  const SizedBox(width: 16),
                  _buildSearchInput(),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Results Summary & Data Grid
            if (displayed.isEmpty)
              _EmptyState(hasQuery: _searchQuery.isNotEmpty)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Results count
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, left: 4),
                    child: Text(
                      'FOUND ${displayed.length} AUDIT LOG ENTRIES',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: context.textMutedColor,
                          letterSpacing: 1),
                    ),
                  ),

                  // Enhanced Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 48), // Padding for expansion icon
                        SizedBox(
                            width: 140,
                            child: Text('INVOICE ID',
                                style: _headerStyle(context))),
                        Expanded(
                            flex: 3,
                            child: Text('CUSTOMER NAME',
                                style: _headerStyle(context))),
                        SizedBox(
                            width: 110,
                            child: Center(
                                child: Text('METHOD',
                                    style: _headerStyle(context)))),
                        SizedBox(
                            width: 120,
                            child: Center(
                                child: Text('TOTAL AMOUNT',
                                    style: _headerStyle(context)))),
                        SizedBox(
                            width: 120,
                            child: Text('DATE & TIME',
                                style: _headerStyle(context))),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),

                  // Sale List
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayed.length,
                    itemBuilder: (ctx, i) {
                      final sale = displayed[i];
                      return Container(
                        decoration: BoxDecoration(
                          color: i.isEven
                              ? Colors.transparent
                              : AppTheme.primary.withValues(alpha: 0.02),
                          border: Border(
                            left: BorderSide(color: context.borderColor),
                            right: BorderSide(color: context.borderColor),
                            bottom: BorderSide(color: context.borderColor),
                          ),
                          borderRadius: i == displayed.length - 1
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(20))
                              : null,
                        ),
                        child: _SaleRow(sale: sale, salesProvider: sales),
                      );
                    },
                  ),

                  // Load More (Fixed into a clean floating style button)
                  if (sales.hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Center(
                        child: OutlinedButton.icon(
                          onPressed: () => sales.loadMore(),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                              'SHOW NEXT ${sales.totalCount - displayed.length} ENTRIES'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilters(SalesProvider sales) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'Today',
            icon: Icons.today_rounded,
            isSelected: sales.activeFilter == SalesFilter.today,
            onTap: () => sales.setFilter(SalesFilter.today),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Yesterday',
            icon: Icons.history_rounded,
            isSelected: sales.activeFilter == SalesFilter.yesterday,
            onTap: () => sales.setFilter(SalesFilter.yesterday),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Last 7 Days',
            icon: Icons.date_range_rounded,
            isSelected: sales.activeFilter == SalesFilter.last7Days,
            onTap: () => sales.setFilter(SalesFilter.last7Days),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'All Time',
            icon: Icons.all_inbox_rounded,
            isSelected: sales.activeFilter == SalesFilter.allTime,
            onTap: () => sales.setFilter(SalesFilter.allTime),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Custom Range',
            icon: Icons.calendar_month_rounded,
            isSelected: sales.activeFilter == SalesFilter.custom,
            onTap: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (range != null)
                sales.setFilter(SalesFilter.custom, range: range);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchInput() {
    return Container(
      width: 320,
      height: 44,
      decoration: BoxDecoration(
        color: context.bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search ID, customer, or method...',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context) => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: context.textMutedColor,
        letterSpacing: 1,
      );

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

// ── KPI Card ────────────────────────────────────────────────────────────────

class _GlassKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String count;
  final double width;

  const _GlassKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.count,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: context.textMutedColor,
                    )),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(count,
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textMutedColor,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.icon,
      required this.isSelected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary
              : context.bgColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppTheme.primary : context.borderColor),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? Colors.white : context.textMutedColor),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : context.textColor,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Sale Row ────────────────────────────────────────────────────────────────

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

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: sale.isReturn
                ? AppTheme.danger.withValues(alpha: 0.1)
                : AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            sale.isReturn
                ? Icons.keyboard_return_rounded
                : Icons.receipt_long_rounded,
            color: sale.isReturn ? AppTheme.danger : AppTheme.primary,
            size: 18,
          ),
        ),
        title: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(sale.invoiceNo,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppTheme.primary)),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  if (sale.isReturn)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.danger.withValues(alpha: 0.2)),
                      ),
                      child: const Text('REFUND',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.danger,
                              letterSpacing: 0.5)),
                    ),
                  Expanded(
                    child: Text(
                      sale.patientName.isEmpty
                          ? 'Walk-in Customer'
                          : sale.patientName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: Center(child: _PaymentBadge(method: sale.paymentMethod)),
            ),
            SizedBox(
              width: 110,
              child: Center(
                child: Text(
                  '₹${sale.total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: sale.isReturn ? AppTheme.danger : AppTheme.success,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.textMutedColor),
              ),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkBg.withValues(alpha: 0.7)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: context.borderColor.withValues(alpha: 0.8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Items and Totals
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('ITEM DESCRIPTION',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: context.textMutedColor,
                                  letterSpacing: 1.0)),
                          const Spacer(),
                          SizedBox(
                              width: 110,
                              child: Text('QTY x PRICE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: context.textMutedColor,
                                      letterSpacing: 1.0),
                                  textAlign: TextAlign.end)),
                          const SizedBox(width: 24),
                          SizedBox(
                              width: 100,
                              child: Text('SUBTOTAL',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: context.textMutedColor,
                                      letterSpacing: 1.0),
                                  textAlign: TextAlign.end)),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                      ...salesProvider.getSaleItems(sale).map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(item.medicineName,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: Text(
                                    '${item.qty} x ₹${item.unitPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.textMutedColor,
                                        fontFamily: 'monospace'),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    '₹${item.lineTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        fontFamily: 'monospace'),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(height: 1),
                      ),
                      if (sale.discount > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('Total Discount',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: context.textMutedColor)),
                              const SizedBox(width: 32),
                              SizedBox(
                                width: 100,
                                child: Text(
                                    '-₹${sale.discount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: AppTheme.danger,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        fontFamily: 'monospace'),
                                    textAlign: TextAlign.end),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Net Amount',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: context.textColor)),
                          const SizedBox(width: 32),
                          SizedBox(
                            width: 120,
                            child: Text('₹${sale.total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primary,
                                    fontSize: 20,
                                    fontFamily: 'monospace'),
                                textAlign: TextAlign.end),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1,
                  height: 140, // Approximate height to match content
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  color: context.borderColor.withValues(alpha: 0.5),
                ),

                // Right Column: Action Buttons
                SizedBox(
                  width: 180,
                  child: Column(
                    children: [
                      _ActionButton(
                        icon: Icons.print_rounded,
                        label: 'Print Receipt',
                        color: AppTheme.primary,
                        isFullWidth: true,
                        onTap: () => PrintingService.instance
                            .printReceipt(context, sale),
                      ),
                      if (!sale.isReturn && canProcessReturns) ...[
                        const SizedBox(height: 12),
                        _ActionButton(
                          icon: Icons.assignment_return_rounded,
                          label: 'Process Return',
                          color: AppTheme.warning,
                          isFullWidth: true,
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => ReturnDialog(originalSale: sale),
                          ),
                        ),
                      ],
                      if (canVoidSales) ...[
                        const SizedBox(height: 12),
                        _ActionButton(
                          icon: Icons.delete_forever_rounded,
                          label: 'Void Sale',
                          color: AppTheme.danger,
                          isFullWidth: true,
                          onTap: () => _confirmDelete(context, inv),
                        ),
                      ],
                    ],
                  ),
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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_rounded,
                  color: AppTheme.danger, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Void Sale', style: TextStyle(color: AppTheme.danger)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete receipt ${sale.invoiceNo}?\n\nThis will refund all inventory quantities and completely remove this record.',
          style: const TextStyle(height: 1.5),
        ),
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: TextStyle(color: context.textMutedColor)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              salesProvider.deleteSale(sale, inv);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('Sale ${sale.invoiceNo} voided successfully.'),
                    ],
                  ),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Void Sale'),
          ),
        ],
      ),
    );
  }
}

// ── Payment Badge ───────────────────────────────────────────────────────────

class _PaymentBadge extends StatelessWidget {
  final String method;
  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (method.toLowerCase()) {
      'cash' => (AppTheme.success, Icons.payments_rounded),
      'upi' => (AppTheme.primary, Icons.qr_code_2_rounded),
      'card' => (AppTheme.accent, Icons.credit_card_rounded),
      'mixed' => (AppTheme.purple, Icons.account_balance_rounded),
      _ => (context.textMutedColor, Icons.payments_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            method.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}

// ── Action Button ───────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isFullWidth;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: isFullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isFullWidth
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  const _EmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(60),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: context.borderColor),
          right: BorderSide(color: context.borderColor),
          bottom: BorderSide(color: context.borderColor),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasQuery ? Icons.search_off_rounded : Icons.receipt_long_rounded,
              size: 40,
              color: AppTheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery ? 'No matching sales found' : 'No sales recorded yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Try adjusting your search query'
                : 'Sales will appear here once transactions are made',
            style: TextStyle(fontSize: 13, color: context.textMutedColor),
          ),
        ],
      ),
    );
  }
}
