import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';

class BulkTransferDialog extends StatefulWidget {
  final WarehouseProvider wh;
  const BulkTransferDialog({super.key, required this.wh});

  @override
  State<BulkTransferDialog> createState() => BulkTransferDialogState();
}

class BulkTransferDialogState extends State<BulkTransferDialog> {
  final Map<int, int> _transferQtys = {}; // medicineId -> qty to transfer
  final Set<int> _selectedIds = {};
  String _searchQuery = '';
  bool _isProcessing = false;
  String _fromLoc = 'bulkClinic';
  String _toLoc = 'clinic';

  final FocusNode _searchFocusNode = FocusNode();
  int _highlightedIndex = 0;
  final Map<int, FocusNode> _qtyFocusNodes = {};

  FocusNode _getQtyFocusNode(int id) {
    return _qtyFocusNodes.putIfAbsent(id, () => FocusNode());
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    for (var fn in _qtyFocusNodes.values) {
      fn.dispose();
    }
    super.dispose();
  }

  void _selectMedicine(Medicine m) {
    setState(() {
      _selectedIds.add(m.id);
      _transferQtys[m.id] = 0;
      _searchQuery = '';
      _highlightedIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getQtyFocusNode(m.id).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final syncService = context.read<SyncService>();

    final locations = const {
      'bulkClinic': 'Clinic Bulk',
      'clinic': 'Clinic',
      'bulkStore': 'Store Bulk',
      'store': 'Store',
    };

    // Get all medicines that have stock in the source location
    final eligibleMeds = inv.rawMedicines.where((m) {
      int stock = 0;
      if (_fromLoc == 'bulkClinic') stock = m.bulkClinicStock;
      if (_fromLoc == 'main' || _fromLoc == 'clinic') stock = m.mainStock;
      if (_fromLoc == 'bulkStore') stock = m.bulkStoreStock;
      if (_fromLoc == 'store') stock = m.storeStock;
      return stock > 0;
    }).toList();

    // Filter by search query
    final filtered = eligibleMeds
        .where((m) =>
            m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            m.barcode.contains(_searchQuery))
        .toList();

    final selectedMedicines =
        inv.rawMedicines.where((m) => _selectedIds.contains(m.id)).toList();

    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            const Icon(Icons.swap_horiz, color: AppTheme.primaryLight),
            const SizedBox(width: 12),
            const Text('Bulk Stock Transfer',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 800,
        height: 650,
        child: _isProcessing
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Processing bulk transfer, please wait...',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      // Colour-coded transfer configuration rows
                      Row(
                        children: [
                          // Source Card (Orange/Amber theme)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.25),
                                    width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.unarchive_outlined,
                                          size: 16, color: Colors.orange),
                                      SizedBox(width: 6),
                                      Text('FROM (SOURCE LOCATION)',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.orange,
                                              letterSpacing: 0.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _fromLoc,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    dropdownColor: context.surfaceColor,
                                    items: locations.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _fromLoc = val;
                                          _selectedIds.clear();
                                          _transferQtys.clear();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 24, color: AppTheme.primaryLight),
                          ),
                          // Destination Card (Indigo/Success theme)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: AppTheme.success
                                        .withValues(alpha: 0.25),
                                    width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.archive_outlined,
                                          size: 16, color: AppTheme.success),
                                      SizedBox(width: 6),
                                      Text('TO (DESTINATION LOCATION)',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.success,
                                              letterSpacing: 0.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _toLoc,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    dropdownColor: context.surfaceColor,
                                    items: locations.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _toLoc = val;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Search & Select All row
                      Row(
                        children: [
                          Expanded(
                            child: Focus(
                              onKeyEvent: (node, event) {
                                if (event is KeyDownEvent) {
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowDown) {
                                    setState(() {
                                      _highlightedIndex =
                                          (_highlightedIndex + 1)
                                              .clamp(0, filtered.length - 1);
                                    });
                                    return KeyEventResult.handled;
                                  } else if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp) {
                                    setState(() {
                                      _highlightedIndex =
                                          (_highlightedIndex - 1)
                                              .clamp(0, filtered.length - 1);
                                    });
                                    return KeyEventResult.handled;
                                  } else if (event.logicalKey ==
                                      LogicalKeyboardKey.enter) {
                                    if (filtered.isNotEmpty &&
                                        _highlightedIndex < filtered.length) {
                                      final m = filtered[_highlightedIndex];
                                      _selectMedicine(m);
                                      return KeyEventResult.handled;
                                    }
                                  }
                                }
                                return KeyEventResult.ignored;
                              },
                              child: TextField(
                                focusNode: _searchFocusNode,
                                autofocus: true,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText:
                                      'Search & Select medicines (Arrows to navigate, Enter to choose)...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onChanged: (v) => setState(() {
                                  _searchQuery = v;
                                  _highlightedIndex = 0;
                                }),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.select_all),
                            label: const Text('Select All'),
                            onPressed: () {
                              setState(() {
                                for (var m in filtered) {
                                  _selectedIds.add(m.id);
                                  _transferQtys[m.id] = 0;
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.percent),
                            label: const Text('50%'),
                            onPressed: () {
                              setState(() {
                                for (var id in _selectedIds) {
                                  final m = inv.rawMedicines
                                      .where((med) => med.id == id)
                                      .firstOrNull;
                                  if (m != null) {
                                    final maxQty = _fromLoc == 'bulkClinic'
                                        ? m.bulkClinicStock
                                        : (_fromLoc == 'main' || _fromLoc == 'clinic'
                                            ? m.mainStock
                                            : (_fromLoc == 'bulkStore'
                                                ? m.bulkStoreStock
                                                : m.storeStock));
                                    _transferQtys[id] = (maxQty * 0.5).round();
                                  }
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            child: const Text('Deselect All'),
                            onPressed: () {
                              setState(() {
                                _selectedIds.clear();
                                _transferQtys.clear();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Selected list section
                      Expanded(
                        child: selectedMedicines.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.playlist_add_rounded,
                                        size: 48,
                                        color: context.textMutedColor),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No items added to transfer list.\nSearch and select medicines above to add them.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: context.textMutedColor,
                                          fontSize: 14),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: selectedMedicines.length,
                                itemBuilder: (ctx, idx) {
                                  final m = selectedMedicines[idx];
                                  final qty = _transferQtys[m.id] ?? 0;

                                  return BulkTransferRow(
                                    key: ValueKey('${m.id}_$_fromLoc'),
                                    medicine: m,
                                    isSelected: true,
                                    isHighlighted: false,
                                    fromLoc: _fromLoc,
                                    toLoc: _toLoc,
                                    initialQty: qty,
                                    focusNode: _getQtyFocusNode(m.id),
                                    onSelectedChanged: (val) {
                                      setState(() {
                                        if (val == false) {
                                          _selectedIds.remove(m.id);
                                          _transferQtys.remove(m.id);
                                        }
                                      });
                                    },
                                    onQtyChanged: (val) {
                                      _transferQtys[m.id] = val;
                                    },
                                    onSubmitted: () {
                                      setState(() {
                                        _searchQuery = '';
                                        _highlightedIndex = 0;
                                      });
                                      _searchFocusNode.requestFocus();
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                  // Dropdown overlay results
                  if (_searchQuery.isNotEmpty && filtered.isNotEmpty)
                    Positioned(
                      top: 195, // Positioned right under the search input
                      left: 0,
                      right:
                          180, // Adjust alignment to match search field width
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: context.borderColor, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            )
                          ],
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                            final m = filtered[idx];
                            final isHighlighted = _highlightedIndex == idx;
                            final maxQty = _fromLoc == 'bulkClinic'
                                ? m.bulkClinicStock
                                : (_fromLoc == 'main' || _fromLoc == 'clinic'
                                    ? m.mainStock
                                    : (_fromLoc == 'bulkStore'
                                        ? m.bulkStoreStock
                                        : m.storeStock));

                            return InkWell(
                              onTap: () {
                                _selectMedicine(m);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                color: isHighlighted
                                    ? AppTheme.primaryLight
                                        .withValues(alpha: 0.08)
                                    : null,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(m.name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                    ),
                                    Text('Stock: $maxQty',
                                        style: TextStyle(
                                            color: context.textMutedColor,
                                            fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: _isProcessing
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style:
                    FilledButton.styleFrom(backgroundColor: AppTheme.success),
                icon: const Icon(Icons.send),
                label: Text('Transfer Selected (${_selectedIds.length})'),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () async {
                        setState(() => _isProcessing = true);
                        int successCount = 0;
                        final failures = <String>[];
                        for (final id in _selectedIds) {
                          final m = inv.rawMedicines
                              .where((med) => med.id == id)
                              .firstOrNull;
                          final qty = _transferQtys[id] ?? 0;
                          if (m != null && qty > 0) {
                            final err = await widget.wh.transfer(
                              medicine: m,
                              qty: qty,
                              from: _fromLoc,
                              to: _toLoc,
                              note: 'Bulk Transfer',
                              syncService: syncService,
                              actor: context.read<AuthProvider>().currentUser,
                            );
                            if (err == null) {
                              successCount++;
                            } else {
                              failures.add('${m.name}: $err');
                            }
                          }
                        }
                        if (mounted) {
                          Navigator.pop(context);
                          if (failures.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Successfully transferred stock for $successCount medicines.'),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          } else {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Bulk Transfer Results'),
                                content: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Successfully transferred: $successCount items.\n'),
                                      const Text('Failed transfers:', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
                                      const SizedBox(height: 8),
                                      ...failures.map((f) => Text('• $f', style: const TextStyle(fontSize: 12))),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        }
                      },
              ),
            ],
    );
  }
}

class BulkTransferRow extends StatefulWidget {
  final Medicine medicine;
  final bool isSelected;
  final bool isHighlighted;
  final String fromLoc;
  final String toLoc;
  final int initialQty;
  final FocusNode focusNode;
  final ValueChanged<bool?> onSelectedChanged;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onSubmitted;

  const BulkTransferRow({
    super.key,
    required this.medicine,
    required this.isSelected,
    required this.isHighlighted,
    required this.fromLoc,
    required this.toLoc,
    required this.initialQty,
    required this.focusNode,
    required this.onSelectedChanged,
    required this.onQtyChanged,
    required this.onSubmitted,
  });

  @override
  State<BulkTransferRow> createState() => BulkTransferRowState();
}

class BulkTransferRowState extends State<BulkTransferRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialQty}');
  }

  @override
  void didUpdateWidget(covariant BulkTransferRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQty != widget.initialQty) {
      _controller.text = '${widget.initialQty}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxQty = widget.fromLoc == 'bulkClinic'
        ? widget.medicine.bulkClinicStock
        : (widget.fromLoc == 'main' || widget.fromLoc == 'clinic'
            ? widget.medicine.mainStock
            : (widget.fromLoc == 'bulkStore'
                ? widget.medicine.bulkStoreStock
                : widget.medicine.storeStock));

    final destQty = widget.toLoc == 'bulkClinic'
        ? widget.medicine.bulkClinicStock
        : (widget.toLoc == 'main' || widget.toLoc == 'clinic'
            ? widget.medicine.mainStock
            : (widget.toLoc == 'bulkStore'
                ? widget.medicine.bulkStoreStock
                : widget.medicine.storeStock));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isHighlighted
              ? AppTheme.primaryLight
              : (widget.isSelected
                  ? AppTheme.primaryLight.withValues(alpha: 0.5)
                  : context.borderColor.withValues(alpha: 0.3)),
          width: widget.isHighlighted || widget.isSelected ? 1.5 : 1,
        ),
      ),
      color: widget.isHighlighted
          ? AppTheme.primaryLight.withValues(alpha: 0.05)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Checkbox(
              value: widget.isSelected,
              onChanged: widget.onSelectedChanged,
              activeColor: AppTheme.primaryLight,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.medicine.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    'Available Stock: $maxQty | Dest Stock: $destQty',
                    style:
                        TextStyle(color: context.textMutedColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (widget.isSelected) ...[
              const Text('Qty:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 8),
              SizedBox(
                width: 75,
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.tab)) {
                      widget.onSubmitted();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: widget.focusNode,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                    onTap: () => _controller.selection = TextSelection(
                        baseOffset: 0, extentOffset: _controller.text.length),
                    onChanged: (val) {
                      final parsed = int.tryParse(val) ?? 0;
                      final clamped = parsed.clamp(0, maxQty);
                      widget.onQtyChanged(clamped);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('/ $maxQty',
                  style:
                      TextStyle(color: context.textMutedColor, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
