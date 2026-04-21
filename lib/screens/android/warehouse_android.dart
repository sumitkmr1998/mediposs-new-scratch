import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/stock_transfer.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';
import 'package:intl/intl.dart';
import '../../widgets/android/medicine_dialog_android.dart';
import '../../shared/widgets/app_status_badge.dart';
import '../../shared/widgets/app_empty_state.dart';

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
      backgroundColor: context.surfaceColor,
      floatingActionButton: auth.hasInventoryWriteAccess
          ? FloatingActionButton.extended(
              onPressed: () =>
                  AndroidMedicineDialog.show(context, medicine: null),
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('NEW MEDICINE',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Warehouse Logistics'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 2 : 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: context.borderColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabs,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  labelColor: AppTheme.primaryLight,
                  unselectedLabelColor: context.textMutedColor,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0),
                  tabs: const [
                    Tab(text: 'STOCK LEVELS'),
                    Tab(text: 'TRANSFERS'),
                  ],
                ),
              ),
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: inv.setSearch,
                  decoration: InputDecoration(
                    hintText: 'Filter inventory...',
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 20, color: AppTheme.primaryLight),
                    filled: true,
                    fillColor: context.borderColor.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _SortDropdown(onChanged: (v) {
                      if (v != null) inv.setSort(v);
                    })),
                    const SizedBox(width: 8),
                    Expanded(child: _FilterDropdownLoc(onChanged: (v) {
                      if (v != null) inv.setFilter(v);
                    })),
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
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _expanded
                ? AppTheme.primaryLight.withValues(alpha: 0.3)
                : context.borderColor.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.medication_liquid_rounded,
                  color: AppTheme.primaryLight, size: 22),
            ),
            title: Text(widget.medicine.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: -0.5)),
            subtitle: Row(
              children: [
                Text(
                    widget.medicine.category.isEmpty
                        ? 'General'
                        : widget.medicine.category,
                    style: TextStyle(
                        fontSize: 11,
                        color: context.textMutedColor,
                        fontWeight: FontWeight.w600)),
                if (widget.medicine.isLowStock) ...[
                  const SizedBox(width: 8),
                  AppStatusBadge(
                    label: 'LOW STOCK',
                    color: AppTheme.warning,
                    style: AppStatusBadgeStyle.text,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ],
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${widget.medicine.sellingPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryLight,
                        fontSize: 16)),
                Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: context.textMutedColor),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                    child: _StockIndicator(
                        label: 'MAIN HUB',
                        value: widget.medicine.mainStock,
                        color: AppTheme.indigo)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StockIndicator(
                        label: 'STORE FRONT',
                        value: widget.medicine.storeStock,
                        color: AppTheme.success,
                        isLow: widget.medicine.isLowStock)),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (widget.auth.hasWarehouseWriteAccess)
                    Row(
                      children: [
                        Expanded(
                            child: _ActionButton(
                          label: 'TO STORE',
                          icon: Icons.storefront_rounded,
                          color: AppTheme.success,
                          onPressed: () => _showTransferDialog(context,
                              widget.medicine, 'main', 'store', widget.wh),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _ActionButton(
                          label: 'BACK TO HUB',
                          icon: Icons.hub_rounded,
                          color: AppTheme.indigo,
                          onPressed: () => _showTransferDialog(context,
                              widget.medicine, 'store', 'main', widget.wh),
                        )),
                      ],
                    ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('REGISTERED BATCHES',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryLight,
                              letterSpacing: 1)),
                    ),
                  ),
                  ...widget.medicine.batches
                      .map((b) => _SimpleBatchRow(batch: b)),
                  if (widget.auth.hasInventoryWriteAccess) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => AndroidMedicineDialog.show(context,
                              medicine: widget.medicine),
                          icon: const Icon(Icons.edit_note_rounded, size: 20),
                          label: const Text('MANAGE BATCHES',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _confirmDelete(
                              context, widget.medicine, widget.inv),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppTheme.danger, size: 20),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Medicine m, InventoryProvider inv) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Medicine',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Permanently remove "${m.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white),
            onPressed: () {
              inv.deleteMedicine(m.id,
                  syncService: context.read<SyncService>());
              Navigator.pop(context);
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _showTransferDialog(BuildContext context, Medicine m, String from,
      String to, WarehouseProvider wh) {
    showDialog(
        context: context,
        builder: (_) =>
            _TransferDialog(medicine: m, from: from, to: to, wh: wh));
  }
}

class _StockIndicator extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool isLow;

  const _StockIndicator(
      {required this.label,
      required this.value,
      required this.color,
      this.isLow = false});

  @override
  Widget build(BuildContext context) {
    final finalColor = isLow ? AppTheme.warning : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: finalColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: finalColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.textMutedColor,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value.toString(),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: finalColor,
                  letterSpacing: -0.5)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}

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
    final toStore = widget.to == 'store';
    final accentColor = toStore ? AppTheme.success : AppTheme.indigo;
    final available = widget.from == 'main'
        ? widget.medicine.mainStock
        : widget.medicine.storeStock;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(
                toStore ? Icons.local_shipping_rounded : Icons.hub_rounded,
                color: accentColor,
                size: 28),
          ),
          const SizedBox(height: 16),
          Text('Stock Transfer',
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text(widget.medicine.name,
              style: TextStyle(
                  fontSize: 13,
                  color: context.textMutedColor,
                  fontWeight: FontWeight.w600)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: context.borderColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LocLabel(label: widget.from == 'main' ? 'HUB' : 'STORE'),
                  Icon(Icons.arrow_forward_rounded,
                      size: 18, color: context.textMutedColor),
                  _LocLabel(
                      label: widget.to == 'main' ? 'HUB' : 'STORE',
                      activeColor: accentColor),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              decoration: InputDecoration(
                labelText: 'TRANSFER QUANTITY',
                suffixText: 'AVAL: $available',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: 'AUDIT NOTE (OPTIONAL)',
                hintText: 'e.g. Weekly Restock',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(120, 44),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () async {
            final qty = int.tryParse(_qtyCtrl.text) ?? 0;
            final err = await widget.wh.transfer(
              medicine: widget.medicine,
              qty: qty,
              from: widget.from,
              to: widget.to,
              note: _noteCtrl.text,
              syncService: context.read<SyncService>(),
            );
            if (!context.mounted) return;
            if (err == null)
              Navigator.pop(context);
            else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(err), backgroundColor: AppTheme.danger));
            }
          },
          child: const Text('CONFIRM',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _LocLabel extends StatelessWidget {
  final String label;
  final Color? activeColor;
  const _LocLabel({required this.label, this.activeColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: activeColor ?? context.textMutedColor,
                letterSpacing: 1)),
        if (activeColor != null)
          Container(
              margin: const EdgeInsets.only(top: 2),
              width: 20,
              height: 2,
              color: activeColor),
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
                  label: 'Past Week',
                  isSelected: wh.activeFilter == SalesFilter.last7Days,
                  onSelected: () => wh.setFilter(SalesFilter.last7Days),
                ),
              ],
            ),
          ),
        ),
        wh.transfers.isEmpty
            ? const SliverFillRemaining(
                child: AppEmptyState(
                  icon: Icons.swap_horiz_rounded,
                  title: 'No transfer records',
                ),
              )
            : SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final t = wh.transfers[i];
                      final isSendOut = t.fromWarehouse == 'main';
                      final accentColor =
                          isSendOut ? AppTheme.success : AppTheme.indigo;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color:
                                  context.borderColor.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Icon(
                                  isSendOut
                                      ? Icons.outbox_rounded
                                      : Icons.move_to_inbox_rounded,
                                  color: accentColor,
                                  size: 20),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.medicineName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14)),
                                  Text(
                                      '${t.fromWarehouse.toUpperCase()} → ${t.toWarehouse.toUpperCase()} • ${t.transferredAt.day}/${t.transferredAt.month}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.textMutedColor,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${isSendOut ? "-" : "+"}${t.qty}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: accentColor,
                                        fontSize: 16)),
                                Text(isSendOut ? 'OUT' : 'IN',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: context.textMutedColor,
                                        letterSpacing: 0.5)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: wh.transfers.length,
                  ),
                ),
              ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final ValueChanged<String?> onChanged;
  const _SortDropdown({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.borderColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: const Text('Sort By',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: TextStyle(
              fontSize: 12,
              color: context.textMutedColor,
              fontWeight: FontWeight.w600),
          items: const [
            DropdownMenuItem(value: 'name', child: Text('Medicine Name')),
            DropdownMenuItem(value: 'stock_low', child: Text('Lowest Stock')),
            DropdownMenuItem(value: 'price_high', child: Text('Highest Price')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _FilterDropdownLoc extends StatelessWidget {
  final ValueChanged<String?> onChanged;
  const _FilterDropdownLoc({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.borderColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: const Text('Filter Area',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: TextStyle(
              fontSize: 12,
              color: context.textMutedColor,
              fontWeight: FontWeight.w600),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Stock')),
            DropdownMenuItem(value: 'low', child: Text('Low Stock Alert')),
            DropdownMenuItem(value: 'out', child: Text('Out of Stock')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SimpleBatchRow extends StatelessWidget {
  final MedicineBatch batch;
  const _SimpleBatchRow({required this.batch});

  @override
  Widget build(BuildContext context) {
    final isExpired = batch.expiryDate.isBefore(DateTime.now());
    final isNear =
        batch.expiryDate.isBefore(DateTime.now().add(const Duration(days: 90)));
    final Color statusColor = isExpired
        ? AppTheme.danger
        : (isNear ? AppTheme.warning : AppTheme.success);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.borderColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(Icons.circle, color: statusColor, size: 8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(batch.batchNo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12)),
                Text('EXP ${DateFormat('MMM yyyy').format(batch.expiryDate)}',
                    style: TextStyle(
                        fontSize: 10,
                        color: statusColor,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Text('${batch.mainStock + batch.storeStock}',
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(width: 4),
          Text('PCS',
              style: TextStyle(
                  fontSize: 10,
                  color: context.textMutedColor,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _FilterChip(
      {required this.label,
      required this.isSelected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : context.textMutedColor)),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primary,
      backgroundColor: context.borderColor.withValues(alpha: 0.05),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
