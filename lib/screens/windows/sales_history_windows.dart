import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/cart_provider.dart';
import '../../shared/providers/navigation_provider.dart';
import '../../shared/models/sale.dart';
import '../../theme/app_theme.dart';
import '../../widgets/return_dialog.dart';
import '../../shared/services/printing_service.dart';
import '../../shared/widgets/app_kpi_card.dart';
import '../../shared/widgets/app_filter_chip.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_status_badge.dart';

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
    final displayed = sales.displayedSales;

    final auth = context.watch<AuthProvider>();
    final bool isCashier = !(auth.currentUser?.canViewHistoricalData ?? true);
    
    // Enforcement: If cashier, lock to today's data
    if (isCashier && sales.activeFilter != SalesFilter.today) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        sales.setFilter(SalesFilter.today);
      });
    }

    double grossSales = 0;
    double returns = 0;
    
    // For Cashier, we force the revenue summary to Today's metrics
    // For others, we calculate based on the current list (search or filter)
    if (isCashier) {
      grossSales = sales.filteredSales.where((s) => _isToday(s.createdAt) && !s.isReturn).fold(0.0, (sum, s) => sum + s.total);
      returns = sales.filteredSales.where((s) => s.isReturn && _isToday(s.createdAt)).fold(0.0, (sum, s) => sum + s.total.abs());
    } else {
      for (final s in sales.filteredSales) {
        if (s.isReturn) {
          returns += s.total.abs();
        } else {
          grossSales += s.total;
        }
      }
    }

    final netTotal = grossSales - returns;
    final saleCount = sales.filteredSales.where((s) => !s.isReturn && (isCashier ? _isToday(s.createdAt) : true)).length;
    final returnCount = sales.filteredSales.where((s) => s.isReturn && (isCashier ? _isToday(s.createdAt) : true)).length;
    final rangeLabel = isCashier ? "Today's" : _getRangeLabel(sales);

    return Scaffold(
      appBar: _buildAppBar(rangeLabel),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKpiSection(grossSales, returns, netTotal, sales, saleCount,
                returnCount, rangeLabel, isCashier),
            const SizedBox(height: 24),
            _buildFilterSearchCard(sales),
            const SizedBox(height: 24),
            _buildDataTable(context, displayed, sales),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String rangeLabel) {
    return AppBar(
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
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text('$rangeLabel overview',
                  style:
                      TextStyle(fontSize: 12, color: context.textMutedColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSection(double grossSales, double returns, double netTotal,
      SalesProvider sales, int saleCount, int returnCount, String rangeLabel, bool isCashier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OVERVIEW',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: context.textMutedColor)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (ctx, constraints) {
          final cols = constraints.maxWidth > 1000
              ? 4
              : (constraints.maxWidth > 700 ? 2 : 1);
          const spacing = 16.0;
          final cardWidth =
              (constraints.maxWidth - (cols - 1) * spacing) / cols;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              AppKpiCard(
                label: 'Gross Sales',
                value: '₹${grossSales.toStringAsFixed(0)}',
                icon: Icons.trending_up_rounded,
                color: AppTheme.primary,
                subtitle: '$saleCount transactions',
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Refunds',
                value: '₹${returns.toStringAsFixed(0)}',
                icon: Icons.keyboard_return_rounded,
                color: AppTheme.danger,
                subtitle: '$returnCount entries',
                width: cardWidth,
              ),
              AppKpiCard(
                label: 'Net Revenue',
                value: '₹${netTotal.toStringAsFixed(0)}',
                icon: Icons.account_balance_wallet_rounded,
                color: AppTheme.success,
                subtitle: isCashier ? "Today's Performance" : '$rangeLabel performance',
                width: cardWidth,
              ),
              if (!isCashier)
                AppKpiCard(
                  label: 'Total Discount',
                  value: '₹${sales.totalDiscount.toStringAsFixed(0)}',
                  icon: Icons.percent_rounded,
                  color: AppTheme.accent,
                  subtitle: 'Lifetime summary',
                  width: cardWidth,
                ),
            ],
          );
        }),
      ],
    );
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  Widget _buildFilterSearchCard(SalesProvider sales) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: context.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      AppFilterChip(
                        label: 'Today',
                        icon: Icons.today_rounded,
                        isSelected: sales.activeFilter == SalesFilter.today,
                        onTap: () => sales.setFilter(SalesFilter.today),
                        style: AppFilterChipStyle.filled,
                      ),
                      if (context.watch<AuthProvider>().currentUser?.canViewHistoricalData ?? true) ...[
                        const SizedBox(width: 8),
                        AppFilterChip(
                          label: 'Yesterday',
                          icon: Icons.history_rounded,
                          isSelected: sales.activeFilter == SalesFilter.yesterday,
                          onTap: () => sales.setFilter(SalesFilter.yesterday),
                          style: AppFilterChipStyle.filled,
                        ),
                        const SizedBox(width: 8),
                        AppFilterChip(
                          label: 'Last 7 Days',
                          icon: Icons.date_range_rounded,
                          isSelected: sales.activeFilter == SalesFilter.last7Days,
                          onTap: () => sales.setFilter(SalesFilter.last7Days),
                          style: AppFilterChipStyle.filled,
                        ),
                        const SizedBox(width: 8),
                        AppFilterChip(
                          label: 'All Time',
                          icon: Icons.all_inbox_rounded,
                          isSelected: sales.activeFilter == SalesFilter.allTime,
                          onTap: () => sales.setFilter(SalesFilter.allTime),
                          style: AppFilterChipStyle.filled,
                        ),
                        const SizedBox(width: 8),
                        AppFilterChip(
                          label: 'Custom',
                          icon: Icons.calendar_month_rounded,
                          isSelected: sales.activeFilter == SalesFilter.custom,
                          onTap: () async {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                              locale: const Locale('en', 'GB'),
                              initialEntryMode: DatePickerEntryMode.input,
                            );
                            if (range != null)
                              sales.setFilter(SalesFilter.custom, range: range);
                          },
                          style: AppFilterChipStyle.filled,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) {
                    setState(() => _searchQuery = v);
                    sales.search(v);
                  },
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search sales...',
                    hintStyle:
                        TextStyle(fontSize: 13, color: context.textMutedColor),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 20, color: context.textMutedColor),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                              sales.search('');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: context.borderColor.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'TRANSACTION TYPE: ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: context.textMutedColor,
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'all',
                    label: Text('All Transactions'),
                    icon: Icon(Icons.all_inbox_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 'retail',
                    label: Text('Retail Sales (GST)'),
                    icon: Icon(Icons.shopping_bag_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 'dispense',
                    label: Text('Clinical Dispenses'),
                    icon: Icon(Icons.medical_services_outlined, size: 16),
                  ),
                ],
                selected: {sales.typeFilter},
                onSelectionChanged: (set) => sales.setTypeFilter(set.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  selectedBackgroundColor: AppTheme.primary,
                  selectedForegroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(
      BuildContext context, List<Sale> displayed, SalesProvider sales) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            'FOUND ${displayed.length} AUDIT LOG ENTRIES',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: context.textMutedColor,
                letterSpacing: 1.5),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border:
                Border.all(color: context.borderColor.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: displayed.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(40),
                  child: AppEmptyState(
                    icon: _searchQuery.isNotEmpty
                        ? Icons.search_off_rounded
                        : Icons.receipt_long_rounded,
                    title: _searchQuery.isNotEmpty
                        ? 'No matching sales found'
                        : 'No sales recorded yet',
                    subtitle: _searchQuery.isNotEmpty
                        ? 'Try adjusting your search query'
                        : 'Sales will appear here once transactions are made',
                    iconColor: AppTheme.primary,
                  ),
                )
              : Column(
                  children: [
                    _buildTableHeader(),
                    Divider(height: 1, color: context.borderColor),
                    ...displayed.asMap().entries.map((e) {
                      final sale = e.value;
                      final isLast = e.key == displayed.length - 1;
                      return Container(
                        decoration: BoxDecoration(
                          color: e.key.isEven
                              ? Colors.transparent
                              : AppTheme.primary.withValues(alpha: 0.02),
                          borderRadius: isLast
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(AppTheme.radiusCard))
                              : null,
                        ),
                        child: _SaleRow(sale: sale, salesProvider: sales),
                      );
                    }),
                    if (sales.hasMore)
                      Padding(
                        padding: const EdgeInsets.all(16),
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
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusCard)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 48),
          SizedBox(
              width: 190,
              child: Text('INVOICE ID', style: _headerStyle(context))),
          Expanded(
              flex: 3,
              child: Text('CUSTOMER NAME', style: _headerStyle(context))),
          const SizedBox(width: 12),
          SizedBox(
              width: 110,
              child:
                  Center(child: Text('METHOD', style: _headerStyle(context)))),
          const SizedBox(width: 12),
          SizedBox(
              width: 120,
              child: Center(
                  child: Text('TOTAL AMOUNT', style: _headerStyle(context)))),
          const SizedBox(width: 12),
          SizedBox(
              width: 120,
              child: Text('DATE & TIME', style: _headerStyle(context))),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  TextStyle _headerStyle(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: context.textMutedColor);

  String _getRangeLabel(SalesProvider sales) {
    if (sales.isSearching) return "Search Result";
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
    return "";
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
    final canEditSales = context.watch<AuthProvider>().canEditSales;
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
              width: 190,
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
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: Center(
                  child: _buildPaymentBadge(sale.paymentMethod, context)),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: Center(
                child: Text(
                  '₹${sale.total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: sale.isReturn ? AppTheme.danger : AppTheme.success,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: Text(
                '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.textMutedColor),
              ),
            ),
            const SizedBox(width: 40),
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
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.medicineName,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                      if (!item.isProcedure && item.batchNo.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            'Batch: ${item.batchNo} | Exp: ${item.expiryDate}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: context.textMutedColor,
                                                fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                    ],
                                  ),
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
                Container(
                  width: 1,
                  height: 140,
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  color: context.borderColor.withValues(alpha: 0.5),
                ),
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
                            .printSaleAsInvoice(context, sale),
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
                      if (canEditSales) ...[
                        const SizedBox(height: 12),
                        _ActionButton(
                          icon: Icons.edit_rounded,
                          label: 'Edit Sale',
                          color: AppTheme.primary,
                          isFullWidth: true,
                          onTap: () {
                            context.read<CartProvider>().loadSaleForEditing(sale);
                            context.read<NavigationProvider>().selectDestination('pos');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Loaded Sale ${sale.invoiceNo} for editing.'),
                                backgroundColor: AppTheme.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
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

  Widget _buildPaymentBadge(String method, BuildContext context) {
    final (Color color, IconData icon) = switch (method.toLowerCase()) {
      'cash' => (AppTheme.success, Icons.payments_rounded),
      'upi' => (AppTheme.primary, Icons.qr_code_2_rounded),
      'card' => (AppTheme.accent, Icons.credit_card_rounded),
      'mixed' => (AppTheme.purple, Icons.account_balance_rounded),
      _ => (
          Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey,
          Icons.payments_outlined
        ),
    };

    return AppStatusBadge(
      label: method.toUpperCase(),
      color: color,
      icon: icon,
      style: AppStatusBadgeStyle.icon,
      fontSize: 10,
      fontWeight: FontWeight.w700,
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
                      color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
