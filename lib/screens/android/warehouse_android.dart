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
import '../../widgets/android/bulk_purchase_dialog_android.dart';
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
      final inv = context.read<InventoryProvider>();
      inv.setSearch('');
      inv.setFilter('all');
      inv.setSort('name');
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
      floatingActionButton: (auth.hasInventoryWriteAccess || auth.canAddStock)
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
      body: RefreshIndicator(
        onRefresh: () async {
          final sync = context.read<SyncService>();
          await sync.syncAll();
          if (mounted) {
            context.read<InventoryProvider>().load();
            context.read<WarehouseProvider>().loadTransfers();
          }
        },
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
            title: const Text('Stock Control'),
            pinned: true,
            floating: true,
            forceElevated: innerBoxIsScrolled,
            elevation: innerBoxIsScrolled ? 2 : 0,
            actions: [
              if (auth.hasInventoryWriteAccess || auth.canAddStock)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: FilledButton.icon(
                    onPressed: () => AndroidBulkPurchaseDialog.show(context),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('BULK ENTRY'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.1),
                      foregroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ],
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
                  child: _CompactStockFlow(
                    title: 'STORE STOCK',
                    bulkLabel: 'BULK',
                    activeLabel: 'ACTIVE',
                    bulkValue: widget.medicine.bulkStoreStock,
                    activeValue: widget.medicine.storeStock,
                    color: const Color(0xFF14B8A6),
                    bulkColor: Colors.teal,
                    isLow: widget.medicine.isLowStock,
                    onTransfer: () => _showTransferDialog(
                        context, widget.medicine, 'bulkStore', 'store', widget.wh),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: 'Transfer Store to Clinic',
                      child: InkWell(
                        onTap: () => _showTransferDialog(
                            context,
                            widget.medicine,
                            'store',
                            'clinic',
                            widget.wh),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 32,
                          height: 22,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded,
                              size: 14, color: Color(0xFF14B8A6)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Tooltip(
                      message: 'Transfer Clinic to Store',
                      child: InkWell(
                        onTap: () => _showTransferDialog(
                            context,
                            widget.medicine,
                            'clinic',
                            'store',
                            widget.wh),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 32,
                          height: 22,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: AppTheme.indigo.withValues(alpha: 0.1),
                          ),
                          child: const Icon(Icons.arrow_back_rounded,
                              size: 14, color: AppTheme.indigo),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactStockFlow(
                    title: 'CLINIC STOCK',
                    bulkLabel: 'BULK',
                    activeLabel: 'ACTIVE',
                    bulkValue: widget.medicine.bulkClinicStock,
                    activeValue: widget.medicine.mainStock,
                    color: AppTheme.indigo,
                    bulkColor: Colors.deepPurple,
                    onTransfer: () => _showTransferDialog(
                        context, widget.medicine, 'bulkClinic', 'clinic', widget.wh),
                  ),
                ),
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.1),
                                foregroundColor: AppTheme.primaryLight,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: AppTheme.primaryLight.withValues(alpha: 0.2)),
                                ),
                              ),
                              onPressed: () => _showTransferDialog(
                                  context, widget.medicine, 'bulkClinic', 'clinic', widget.wh),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: const Text('TRANSFER STOCK',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      letterSpacing: 1)),
                            ),
                          ),
                        ],
                      ),
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
                  if (widget.auth.hasInventoryWriteAccess || widget.auth.canAddStock) ...[
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

class _CompactStockFlow extends StatelessWidget {
  final String title;
  final String bulkLabel;
  final String activeLabel;
  final int bulkValue;
  final int activeValue;
  final Color color;
  final Color bulkColor;
  final bool isLow;
  final VoidCallback onTransfer;

  const _CompactStockFlow({
    required this.title,
    required this.bulkLabel,
    required this.activeLabel,
    required this.bulkValue,
    required this.activeValue,
    required this.color,
    required this.bulkColor,
    this.isLow = false,
    required this.onTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isLow ? AppTheme.warning : color;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: activeColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: activeColor,
                  letterSpacing: 0.8,
                ),
              ),
              if (isLow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LOW',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bulkLabel,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: context.textMutedColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bulkValue.toString(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: bulkColor,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onTransfer,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor.withValues(alpha: 0.08),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: activeColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      activeLabel,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: context.textMutedColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activeValue.toString(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: activeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
  MedicineBatch? _selectedBatch;
  late String _fromLoc;
  late String _toLoc;
  bool _isSubmitting = false;

  int _getStock(MedicineBatch b, String loc) {
    if (loc == 'main' || loc == 'clinic') return b.mainStock;
    if (loc == 'store') return b.storeStock;
    if (loc == 'bulkClinic') return b.bulkClinicStock;
    if (loc == 'bulkStore') return b.bulkStoreStock;
    return 0;
  }

  void _updateSelectedBatch() {
    final availableBatches = widget.medicine.batches.where((b) =>
        _getStock(b, _fromLoc) > 0).toList();
    if (availableBatches.isNotEmpty) {
      availableBatches.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      _selectedBatch = availableBatches.first;
    } else {
      _selectedBatch = widget.medicine.batches.isNotEmpty ? widget.medicine.batches.first : null;
    }
  }

  @override
  void initState() {
    super.initState();
    _fromLoc = widget.from;
    _toLoc = widget.to;
    _updateSelectedBatch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _qtyCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtyCtrl.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final locations = const {
      'bulkClinic': 'Clinic Bulk',
      'clinic': 'Clinic',
      'bulkStore': 'Store Bulk',
      'store': 'Store',
    };

    final available = _selectedBatch != null
        ? _getStock(_selectedBatch!, _fromLoc)
        : (_fromLoc == 'main' || _fromLoc == 'clinic'
            ? widget.medicine.mainStock
            : (_fromLoc == 'store'
                ? widget.medicine.storeStock
                : (_fromLoc == 'bulkClinic'
                    ? widget.medicine.bulkClinicStock
                    : widget.medicine.bulkStoreStock)));

    final toStore = _toLoc == 'store' || _toLoc == 'bulkStore';
    final accentColor = toStore ? AppTheme.success : AppTheme.indigo;

    final availableBatches = widget.medicine.batches.where((b) =>
        _getStock(b, _fromLoc) > 0).toList();

    final fieldDeco = InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
      filled: true,
      fillColor: context.borderColor.withValues(alpha: 0.03),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          Icon(
            toStore ? Icons.local_shipping_rounded : Icons.medical_services_rounded,
            color: accentColor,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stock Transfer',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(widget.medicine.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: context.textMutedColor,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _fromLoc,
                    decoration: fieldDeco.copyWith(
                      labelText: 'From',
                    ),
                    dropdownColor: context.surfaceColor,
                    style: const TextStyle(fontSize: 12, color: AppTheme.primaryLight, fontWeight: FontWeight.w600),
                    items: locations.entries.map((e) {
                      return DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _fromLoc = val;
                          _updateSelectedBatch();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _toLoc,
                    decoration: fieldDeco.copyWith(
                      labelText: 'To',
                    ),
                    dropdownColor: context.surfaceColor,
                    style: const TextStyle(fontSize: 12, color: AppTheme.primaryLight, fontWeight: FontWeight.w600),
                    items: locations.entries.map((e) {
                      return DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _toLoc = val;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (availableBatches.isNotEmpty) ...[
              DropdownButtonFormField<MedicineBatch>(
                value: _selectedBatch,
                decoration: fieldDeco.copyWith(
                  labelText: 'Batch',
                ),
                dropdownColor: context.surfaceColor,
                isExpanded: true,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppTheme.primaryLight),
                items: availableBatches.map((b) {
                  final stock = _getStock(b, _fromLoc);
                  final expiryStr = DateFormat('MM/yy').format(b.expiryDate);
                  return DropdownMenuItem<MedicineBatch>(
                    value: b,
                    child: Text(
                      '${b.batchNo} ($expiryStr) [Qty: $stock]',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                }).toList(),
                onChanged: (b) {
                  setState(() {
                    _selectedBatch = b;
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final current = int.tryParse(_qtyCtrl.text) ?? 0;
                    if (current > 1) {
                      setState(() {
                        _qtyCtrl.text = (current - 1).toString();
                      });
                      _qtyCtrl.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _qtyCtrl.text.length,
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(4, 12, 12, 12),
                    child: Icon(Icons.remove_circle_outline, color: AppTheme.danger),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    onTap: () {
                      _qtyCtrl.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _qtyCtrl.text.length,
                      );
                    },
                    decoration: fieldDeco.copyWith(
                      labelText: 'Transfer Quantity',
                      suffixText: 'Max: $available',
                      suffixStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primaryLight),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final current = int.tryParse(_qtyCtrl.text) ?? 0;
                    if (current < available) {
                      setState(() {
                        _qtyCtrl.text = (current + 1).toString();
                      });
                      _qtyCtrl.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: _qtyCtrl.text.length,
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 4, 12),
                    child: Icon(Icons.add_circle_outline, color: AppTheme.success),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: fieldDeco.copyWith(
                labelText: 'Audit Note (Optional)',
                hintText: 'e.g. Restock',
                hintStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(100, 36),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isSubmitting
              ? null
              : () async {
                  if (availableBatches.isNotEmpty && _selectedBatch == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Please select a batch to transfer'),
                      backgroundColor: AppTheme.danger,
                    ));
                    return;
                  }
                  setState(() => _isSubmitting = true);
                  try {
                    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
                    final err = await widget.wh.transfer(
                      medicine: widget.medicine,
                      qty: qty,
                      from: _fromLoc,
                      to: _toLoc,
                      batchNo: _selectedBatch?.batchNo,
                      expiryDate: _selectedBatch?.expiryDate,
                      note: _noteCtrl.text,
                      syncService: context.read<SyncService>(),
                      actor: context.read<AuthProvider>().currentUser,
                    );
                    if (!context.mounted) return;
                    if (err == null) {
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(err), backgroundColor: AppTheme.danger));
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isSubmitting = false);
                    }
                  }
                },
          child: const Text('CONFIRM',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
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
                      final isSendOut = t.fromWarehouse == 'main' || t.fromWarehouse == 'clinic';
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
