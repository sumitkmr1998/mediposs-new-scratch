import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/hub_provider.dart';
import '../theme/app_theme.dart';
import 'medicine_detail_screen.dart';

class MedicinesListScreen extends StatefulWidget {
  const MedicinesListScreen({super.key});

  @override
  State<MedicinesListScreen> createState() => _MedicinesListScreenState();
}

class _MedicinesListScreenState extends State<MedicinesListScreen> {
  String _search = '';
  String _sortBy = 'name';
  bool _showLowStockOnly = false;

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<HubProvider>();

    var filtered = hub.medicines.where((m) {
      if (_showLowStockOnly && !m.isLowStock) return false;
      if (_search.isEmpty) return true;
      return m.name.toLowerCase().contains(_search.toLowerCase()) ||
          m.category.toLowerCase().contains(_search.toLowerCase()) ||
          m.barcode.contains(_search);
    }).toList();

    // Sort
    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'stock':
        filtered.sort((a, b) => a.totalStock.compareTo(b.totalStock));
        break;
      case 'margin':
        filtered.sort((a, b) => b.marginPercent.compareTo(a.marginPercent));
        break;
      case 'sales':
        filtered.sort(
          (a, b) => hub.totalUnitsSold(b.id).compareTo(hub.totalUnitsSold(a.id)),
        );
        break;
    }

    return Column(
      children: [
        // Modern search bar with filters
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            boxShadow: [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search medicines, categories, barcodes...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() => _search = ''),
                              )
                            : null,
                        filled: true,
                        fillColor: AppTheme.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildSortDropdown(),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('Low Stock Only'),
                    selected: _showLowStockOnly,
                    onSelected: (v) => setState(() => _showLowStockOnly = v),
                    selectedColor: AppTheme.danger.withValues(alpha: 0.1),
                    checkmarkColor: AppTheme.danger,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _showLowStockOnly
                          ? AppTheme.danger
                          : AppTheme.textSecondary,
                      fontWeight: _showLowStockOnly
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                    backgroundColor: AppTheme.surfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: _showLowStockOnly
                            ? AppTheme.danger.withValues(alpha: 0.3)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.medication,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Showing ${filtered.length} of ${hub.medicines.length} medicines',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_showLowStockOnly)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning,
                            size: 12,
                            color: AppTheme.danger,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Low Stock',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        // Medicine List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: AppTheme.textTertiary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No medicines found',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _search.isNotEmpty
                            ? 'Try a different search term'
                            : 'Add medicines to your catalog',
                        style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => hub.refreshData(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final m = filtered[index];
                      final unitsSold = hub.totalUnitsSold(m.id);
                      final daysLeft = hub.daysOfStockRemaining(m.id);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: m.isLowStock
                                ? AppTheme.danger.withValues(alpha: 0.2)
                                : AppTheme.surfaceVariant,
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MedicineDetailScreen(medicine: m),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Icon/Avatar
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: m.isLowStock
                                          ? [
                                              AppTheme.danger.withValues(alpha: 0.1),
                                              AppTheme.danger.withValues(alpha: 0.05),
                                            ]
                                          : [
                                              AppTheme.primary.withValues(alpha: 0.1),
                                              AppTheme.primary.withValues(alpha: 0.05),
                                            ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: m.isLowStock
                                          ? AppTheme.danger.withValues(alpha: 0.2)
                                          : AppTheme.primary.withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.medication,
                                    color: m.isLowStock
                                        ? AppTheme.danger
                                        : AppTheme.primary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Main info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: AppTheme.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surfaceVariant,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              m.category,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '• ${m.unit}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.textTertiary,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppTheme.success.withValues(
                                                alpha: 0.1,
                                              ),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${m.marginPercent.toStringAsFixed(0)}%',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.success,
                                              ),
                                            ),
                                          ),
                                          if (m.hasExpiredBatch || m.hasNearExpiryBatch) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: (m.hasExpiredBatch
                                                        ? AppTheme.danger
                                                        : Colors.orange)
                                                    .withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: (m.hasExpiredBatch
                                                              ? AppTheme.danger
                                                              : Colors.orange)
                                                          .withValues(alpha: 0.2),
                                                ),
                                              ),
                                              child: Text(
                                                m.hasExpiredBatch
                                                    ? 'EXPIRED'
                                                    : 'NEAR EXPIRY',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: m.hasExpiredBatch
                                                      ? AppTheme.danger
                                                      : Colors.orange,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Stats
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.inventory_2,
                                          size: 14,
                                          color: m.isLowStock
                                              ? AppTheme.danger
                                              : AppTheme.info,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${m.totalStock}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: m.isLowStock
                                                ? AppTheme.danger
                                                : AppTheme.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.shopping_cart,
                                          size: 12,
                                          color: AppTheme.success,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Sold: $unitsSold',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      daysLeft >= 999
                                          ? '∞ days left'
                                          : '${daysLeft.toStringAsFixed(0)}d left',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: daysLeft < 7
                                            ? AppTheme.danger
                                            : AppTheme.success,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right,
                                  size: 20,
                                  color: AppTheme.textTertiary.withValues(alpha: 0.6),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSortDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: DropdownButton<String>(
        value: _sortBy,
        underline: const SizedBox(),
        icon: Icon(
          Icons.sort,
          size: 18,
          color: AppTheme.textSecondary,
        ),
        items: const [
          DropdownMenuItem(
            value: 'name',
            child: Text('Sort: Name', style: TextStyle(fontSize: 13)),
          ),
          DropdownMenuItem(
            value: 'stock',
            child: Text('Sort: Stock', style: TextStyle(fontSize: 13)),
          ),
          DropdownMenuItem(
            value: 'margin',
            child: Text('Sort: Margin', style: TextStyle(fontSize: 13)),
          ),
          DropdownMenuItem(
            value: 'sales',
            child: Text('Sort: Sales', style: TextStyle(fontSize: 13)),
          ),
        ],
        onChanged: (v) => setState(() => _sortBy = v ?? 'name'),
      ),
    );
  }
}