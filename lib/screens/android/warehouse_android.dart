import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/android/medicine_dialog_android.dart';

class WarehouseAndroid extends StatefulWidget {
  const WarehouseAndroid({super.key});

  @override
  State<WarehouseAndroid> createState() => _WarehouseAndroidState();
}

class _WarehouseAndroidState extends State<WarehouseAndroid>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WarehouseProvider>().loadTransfers();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: context.surfaceColor, // Seamless background
      floatingActionButton: auth.hasInventoryWriteAccess
          ? FloatingActionButton(
              onPressed: () {
                AndroidMedicineDialog.show(context, medicine: null);
              },
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Warehouse Control'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 4 : 0,
            bottom: TabBar(
              controller: _tabs,
              labelColor: AppTheme.primary,
              unselectedLabelColor: context.textMutedColor,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_customize), text: 'Overview'),
                Tab(icon: Icon(Icons.history_toggle_off), text: 'Transfers'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: const [
            _StockLevelsTab(),
            _TransferHistoryTab(),
          ],
        ),
      ),
    );
  }
}

class _StockLevelsTab extends StatelessWidget {
  const _StockLevelsTab();

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final wh = context.read<WarehouseProvider>();
    final auth = context.watch<AuthProvider>();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: inv.setSearch,
                  decoration: InputDecoration(
                    hintText: 'Search medicine...',
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: context.surfaceColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SortDropdown(
                        onChanged: inv.setSort,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FilterDropdownLoc(
                        onChanged: inv.setFilter,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final m = inv.medicines[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModernMedicineCard(
                      medicine: m, wh: wh, auth: auth, inv: inv),
                );
              },
              childCount: inv.medicines.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class _ModernMedicineCard extends StatefulWidget {
  final Medicine medicine;
  final WarehouseProvider wh;
  final AuthProvider auth;
  final InventoryProvider inv;

  const _ModernMedicineCard(
      {required this.medicine,
      required this.wh,
      required this.auth,
      required this.inv});

  @override
  State<_ModernMedicineCard> createState() => _ModernMedicineCardState();
}

class _ModernMedicineCardState extends State<_ModernMedicineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
            color: _expanded
                ? AppTheme.primary.withValues(alpha: 0.5)
                : context.borderColor.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _expanded = !_expanded;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.vaccines,
                          color: AppTheme.primaryLight),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.medicine.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.medicine.category.isEmpty
                                ? 'Uncategorized'
                                : widget.medicine.category,
                            style: TextStyle(
                                color: context.textMutedColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                          if (widget.medicine.isLowStock) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_downward,
                                      size: 14, color: AppTheme.warning),
                                  SizedBox(width: 4),
                                  Text('LOW STOCK',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: AppTheme.warning)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      '₹${widget.medicine.sellingPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: context.textMutedColor,
                    ),
                  ],
                ),
              ),

              // Stock Metrics
              Container(
                padding: EdgeInsets.symmetric(vertical: _expanded ? 16 : 8),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  border: Border.symmetric(
                    horizontal: BorderSide(
                        color: context.borderColor.withValues(alpha: 0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricColumn(
                        label: 'Main Hub',
                        value: widget.medicine.mainStock,
                        icon: Icons.warehouse,
                        color: const Color(0xFF6366F1),
                        isExpanded: _expanded,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: _expanded ? 40 : 24,
                      color: context.borderColor.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: _MetricColumn(
                        label: 'Store Front',
                        value: widget.medicine.storeStock,
                        icon: Icons.storefront,
                        color: const Color(0xFF14B8A6),
                        isWarning: widget.medicine.isLowStock,
                        isExpanded: _expanded,
                      ),
                    ),
                  ],
                ),
              ),

              // Actions
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: !_expanded
                    ? const SizedBox(width: double.infinity)
                    : ((widget.auth.hasWarehouseWriteAccess ||
                            widget.auth.hasInventoryWriteAccess)
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                if (widget.auth.hasWarehouseWriteAccess)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _showTransferDialog(
                                              context,
                                              widget.medicine,
                                              'main',
                                              'store',
                                              widget.wh),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF14B8A6)
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: const Color(0xFF14B8A6)
                                                      .withValues(alpha: 0.2)),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text('Send to Store',
                                                    style: TextStyle(
                                                        color:
                                                            Color(0xFF14B8A6),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13)),
                                                SizedBox(width: 8),
                                                Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 16,
                                                    color: Color(0xFF14B8A6)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => _showTransferDialog(
                                              context,
                                              widget.medicine,
                                              'store',
                                              'main',
                                              widget.wh),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF6366F1)
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: const Color(0xFF6366F1)
                                                      .withValues(alpha: 0.2)),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.arrow_back_rounded,
                                                    size: 16,
                                                    color: Color(0xFF6366F1)),
                                                SizedBox(width: 8),
                                                Text('Return to Main',
                                                    style: TextStyle(
                                                        color:
                                                            Color(0xFF6366F1),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (widget.auth.hasInventoryWriteAccess) ...[
                                  if (widget.auth.hasWarehouseWriteAccess)
                                    const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        icon: const Icon(Icons.edit, size: 16),
                                        label: const Text('Edit'),
                                        onPressed: () {
                                          AndroidMedicineDialog.show(context,
                                              medicine: widget.medicine);
                                        },
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.delete,
                                            size: 16, color: AppTheme.danger),
                                        label: const Text('Delete',
                                            style: TextStyle(
                                                color: AppTheme.danger)),
                                        onPressed: () {
                                          _confirmDelete(context,
                                              widget.medicine, widget.inv);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Medicine m, InventoryProvider inv) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Medicine',
            style: TextStyle(color: AppTheme.danger)),
        content: Text('Delete "${m.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              final sync = context.read<SyncService>();
              inv.deleteMedicine(m.id, syncService: sync);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showTransferDialog(BuildContext context, Medicine m, String from,
      String to, WarehouseProvider wh) {
    showDialog(
      context: context,
      builder: (_) => _TransferDialog(medicine: m, from: from, to: to, wh: wh),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool isWarning;
  final bool isExpanded;

  const _MetricColumn({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isWarning = false,
    this.isExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final finalColor = isWarning ? AppTheme.warning : color;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: isExpanded ? 14 : 12, color: context.textMutedColor),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: isExpanded ? 12 : 10,
                    fontWeight: FontWeight.w600,
                    color: context.textMutedColor)),
          ],
        ),
        SizedBox(height: isExpanded ? 6 : 2),
        Text('$value',
            style: TextStyle(
                fontSize: isExpanded ? 22 : 15,
                fontWeight: FontWeight.w900,
                color: finalColor)),
      ],
    );
  }
}

// ─── Transfer Dialog ───────────────────────────────────────────────────────────
class _TransferDialog extends StatefulWidget {
  final Medicine medicine;
  final String from;
  final String to;
  final WarehouseProvider wh;

  const _TransferDialog(
      {required this.medicine,
      required this.from,
      required this.to,
      required this.wh});

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final fromLabel = widget.from == 'main' ? 'Main Warehouse' : 'Store Stock';
    final toLabel = widget.to == 'main' ? 'Main Warehouse' : 'Store Stock';
    final available = widget.from == 'main'
        ? widget.medicine.mainStock
        : widget.medicine.storeStock;
    final primaryColor = widget.to == 'store'
        ? const Color(0xFF14B8A6)
        : const Color(0xFF6366F1);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.swap_horiz, color: primaryColor),
          const SizedBox(width: 8),
          Expanded(child: Text('Transfer ${widget.medicine.name}')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('From',
                          style: TextStyle(
                              fontSize: 11, color: context.textMutedColor)),
                      Text(fromLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    size: 14, color: primaryColor.withValues(alpha: 0.5)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To',
                          style: TextStyle(
                              fontSize: 11, color: context.textMutedColor)),
                      Text(toLabel,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: primaryColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Available to transfer: $available ${widget.medicine.unit}',
              style: TextStyle(
                  color: context.textMutedColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _qtyCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Quantity to Transfer',
              hintText: 'e.g. 50',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: context.surfaceColor,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Reason for transfer...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: context.surfaceColor,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: context.textMutedColor))),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () async {
            final qty = int.tryParse(_qtyCtrl.text) ?? 0;
            final sync = context.read<SyncService>();
            final err = await widget.wh.transfer(
              medicine: widget.medicine,
              qty: qty,
              from: widget.from,
              to: widget.to,
              note: _noteCtrl.text,
              syncService: sync,
            );
            if (!context.mounted) return;
            if (err != null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(err),
                backgroundColor: AppTheme.danger,
                behavior: SnackBarBehavior.floating,
              ));
            } else {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Stock transferred successfully'),
                  ],
                ),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            }
          },
          child: const Text('Confirm Transfer'),
        ),
      ],
    );
  }
}

class _TransferHistoryTab extends StatelessWidget {
  const _TransferHistoryTab();

  @override
  Widget build(BuildContext context) {
    final wh = context.watch<WarehouseProvider>();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Today',
                  isSelected: wh.activeFilter == SalesFilter.today,
                  onSelected: () => wh.setFilter(SalesFilter.today),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Yesterday',
                  isSelected: wh.activeFilter == SalesFilter.yesterday,
                  onSelected: () => wh.setFilter(SalesFilter.yesterday),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Last 7 Days',
                  isSelected: wh.activeFilter == SalesFilter.last7Days,
                  onSelected: () => wh.setFilter(SalesFilter.last7Days),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'All Time',
                  isSelected: wh.activeFilter == SalesFilter.allTime,
                  onSelected: () => wh.setFilter(SalesFilter.allTime),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Custom',
                  isSelected: wh.activeFilter == SalesFilter.custom,
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
                      wh.setFilter(SalesFilter.custom, range: range);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        wh.transfers.isEmpty
            ? SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history,
                          size: 64,
                          color: context.textMutedColor.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('No transfers in this period',
                          style: TextStyle(
                              color: context.textMutedColor,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              )
            : SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final t = wh.transfers[i];
                      final isSendOut = t.fromWarehouse == 'main';
                      final color = isSendOut
                          ? const Color(0xFF14B8A6)
                          : const Color(0xFF6366F1);
                      final icon = isSendOut
                          ? Icons.arrow_forward_rounded
                          : Icons.arrow_back_rounded;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  context.borderColor.withValues(alpha: 0.5)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          title: Text(t.medicineName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${t.fromWarehouse.toUpperCase()} → ${t.toWarehouse.toUpperCase()}\n${t.note.isNotEmpty ? t.note : "No note attached"}',
                              style: TextStyle(
                                  color: context.textMutedColor,
                                  height: 1.4,
                                  fontSize: 12)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('+${t.qty}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      color: color)),
                              const SizedBox(height: 4),
                              Text(
                                '${t.transferredAt.day}/${t.transferredAt.month}/${t.transferredAt.year}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: context.textMutedColor,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    childCount: wh.transfers.length,
                  ),
                ),
              ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : context.textMutedColor,
          )),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primary,
      backgroundColor: context.surfaceColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : context.borderColor,
        ),
      ),
      showCheckmark: false,
    );
  }
}

class _FilterDropdownLoc extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _FilterDropdownLoc({required this.onChanged});

  @override
  State<_FilterDropdownLoc> createState() => _FilterDropdownLocState();
}

class _FilterDropdownLocState extends State<_FilterDropdownLoc> {
  String _selected = 'all';
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selected,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.filter_list, size: 20),
          onChanged: (v) {
            if (v != null) {
              setState(() => _selected = v);
              widget.onChanged(v);
            }
          },
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Stock')),
            DropdownMenuItem(value: 'low-stock', child: Text('Low Stock')),
            DropdownMenuItem(value: 'main-empty', child: Text('Main Empty')),
          ],
        ),
      ),
    );
  }
}

class _SortDropdown extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _SortDropdown({required this.onChanged});

  @override
  State<_SortDropdown> createState() => _SortDropdownState();
}

class _SortDropdownState extends State<_SortDropdown> {
  String _selected = 'name';
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selected,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.sort, size: 20),
          onChanged: (v) {
            if (v != null) {
              setState(() => _selected = v);
              widget.onChanged(v);
            }
          },
          items: const [
            DropdownMenuItem(value: 'name', child: Text('Sort: Name')),
            DropdownMenuItem(
                value: 'price', child: Text('Sort: Highest Price')),
            DropdownMenuItem(value: 'stock', child: Text('Sort: Lowest Stock')),
          ],
        ),
      ),
    );
  }
}
