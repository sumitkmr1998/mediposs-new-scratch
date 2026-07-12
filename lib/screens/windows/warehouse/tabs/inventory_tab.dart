import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/warehouse_provider.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../theme/app_theme.dart';
import '../widgets/medicine_card.dart';

class StockLevelsTab extends StatefulWidget {
  const StockLevelsTab({super.key});

  @override
  State<StockLevelsTab> createState() => StockLevelsTabState();
}

class StockLevelsTabState extends State<StockLevelsTab> {
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final inv = context.read<InventoryProvider>();
        inv.setSearch('');
        inv.setFilter('all');
        inv.setSort('name');
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryProvider>();
    final wh = context.read<WarehouseProvider>();
    final auth = context.watch<AuthProvider>();
    final sales = context.watch<SalesProvider>().rawSales;
    final filteredMeds = inv.getFilteredMedicines(sales);

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
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      onChanged: inv.setSearch,
                      decoration: InputDecoration(
                        hintText: 'Search by name or barcode...',
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
                  Expanded(
                    child: HorizontalDropdown(
                      label: 'Sort By',
                      value: inv.sortBy,
                      items: const {
                        'name': 'Name (A-Z)',
                        'price': 'Price (High-Low)',
                        'stock': 'Stock (Low-High)',
                      },
                      onChanged: (v) => inv.setSort(v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: HorizontalDropdown(
                      label: 'Filter',
                      value: inv.filterWarehouse,
                      items: const {
                        'all': 'All Stock',
                        'low-stock': 'Low Stock Alert',
                        'main-empty': 'Clinic Empty',
                        'expired': 'Expired',
                        'near-expiry': 'Near Expiry',
                      },
                      onChanged: (v) => inv.setFilter(v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Reconcile Clinic Quantity with Batches',
                    icon:
                        const Icon(Icons.rebase_edit, color: AppTheme.primary),
                    onPressed: () {
                      inv.reconcileAllStock();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Stock reconciled with batches successfully')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Medicines Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisSpacing: 24,
              crossAxisSpacing: 24,
              mainAxisExtent: 430, // Fixed height for consistency
            ),
            itemCount: filteredMeds.length,
            itemBuilder: (ctx, i) {
              final m = filteredMeds[i];
              return ModernMedicineCardWindows(
                medicine: m,
                wh: wh,
                auth: auth,
                inv: inv,
                isSelected: _selectedIds.contains(m.id),
                onSelect: (selected) => _toggleSelection(m.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class HorizontalDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;

  const HorizontalDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: context.textMutedColor)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.bgColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: items.entries.map((e) {
                return DropdownMenuItem(value: e.key, child: Text(e.value));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
