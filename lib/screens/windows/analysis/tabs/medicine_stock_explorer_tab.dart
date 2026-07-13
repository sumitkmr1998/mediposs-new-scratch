import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/models/sale.dart';
import '../../../../shared/providers/sales_provider.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/utils/analytics_helper.dart';
import '../../../../theme/app_theme.dart';
import '../../../../shared/widgets/app_status_badge.dart';
import 'package:flutter/services.dart';

class MedicineStockExplorerTab extends StatefulWidget {
  const MedicineStockExplorerTab({super.key});

  @override
  State<MedicineStockExplorerTab> createState() => _MedicineStockExplorerTabState();
}

class _MedicineStockExplorerTabState extends State<MedicineStockExplorerTab> {
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name', 'stock', 'velocity', 'timeline'
  Medicine? _selectedMedicine;
  double _leftPaneWidth = 380.0;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? _lastSalesLength;
  final Map<int, double> _velocitiesCache = {};
  final Map<int, double> _timelinesCache = {};

  double _getVelocity(Medicine m, List<Sale> sales) {
    if (_lastSalesLength != sales.length) {
      _velocitiesCache.clear();
      _timelinesCache.clear();
      _lastSalesLength = sales.length;
    }
    return _velocitiesCache.putIfAbsent(m.id, () => AnalyticsHelper.dailyConsumptionRate(m.id, sales, trendDays: 30));
  }

  double _getTimeline(Medicine m, List<Sale> sales) {
    if (_lastSalesLength != sales.length) {
      _velocitiesCache.clear();
      _timelinesCache.clear();
      _lastSalesLength = sales.length;
    }
    return _timelinesCache.putIfAbsent(m.id, () => AnalyticsHelper.daysOfStockRemaining(m, sales, trendDays: 30));
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final sales = context.watch<SalesProvider>().rawSales;
    final medicines = inventory.rawMedicines;

    // Filter medicines
    final filtered = medicines.where((m) {
      final q = _searchQuery.toLowerCase().trim();
      return m.name.toLowerCase().contains(q) ||
          m.barcode.contains(q) ||
          m.category.toLowerCase().contains(q);
    }).toList();

    // Sort medicines
    filtered.sort((a, b) {
      if (_sortBy == 'stock') {
        return b.totalStock.compareTo(a.totalStock);
      } else if (_sortBy == 'velocity') {
        final velA = _getVelocity(a, sales);
        final velB = _getVelocity(b, sales);
        return velB.compareTo(velA);
      } else if (_sortBy == 'timeline') {
        final daysA = _getTimeline(a, sales);
        final daysB = _getTimeline(b, sales);
        return daysA.compareTo(daysB);
      } else {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });

    // Default selection
    if (_selectedMedicine == null && filtered.isNotEmpty) {
      _selectedMedicine = filtered.first;
    } else if (_selectedMedicine != null && !filtered.any((x) => x.id == _selectedMedicine!.id)) {
      _selectedMedicine = filtered.isNotEmpty ? filtered.first : null;
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _selectNext(filtered);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _selectPrevious(filtered);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        children: [
        // Left Pane (Search, Sort, List)
        SizedBox(
          width: _leftPaneWidth,
          child: Container(
            decoration: BoxDecoration(
              color: context.surfaceColor,
            ),
            child: Column(
              children: [
                // Header (Search & Sort)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search medicine by name or barcode...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: context.bgColor.withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text('Sort:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildSortChip('Name', 'name'),
                                  const SizedBox(width: 6),
                                  _buildSortChip('Total Stock', 'stock'),
                                  const SizedBox(width: 6),
                                  _buildSortChip('Velocity', 'velocity'),
                                  const SizedBox(width: 6),
                                  _buildSortChip('Timeline', 'timeline'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // List
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No medicines found.'))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (context, idx) {
                             final m = filtered[idx];
                             final isSelected = _selectedMedicine?.id == m.id;
                             final velocity = _getVelocity(m, sales);
                             final daysLeft = _getTimeline(m, sales);
                            
                            Color timelineColor = Colors.green;
                            String timelineText = 'Safe';
                            if (velocity > 0) {
                              if (daysLeft < 7) {
                                timelineColor = AppTheme.danger;
                                timelineText = '${daysLeft.toStringAsFixed(0)}d (Crit)';
                              } else if (daysLeft < 15) {
                                timelineColor = AppTheme.orange;
                                timelineText = '${daysLeft.toStringAsFixed(0)}d (Urg)';
                              } else if (daysLeft < 30) {
                                timelineColor = AppTheme.warning;
                                timelineText = '${daysLeft.toStringAsFixed(0)}d (Depl)';
                              } else {
                                timelineText = '${(daysLeft / 30).toStringAsFixed(1)}mo';
                              }
                            } else {
                              timelineColor = Colors.grey;
                              timelineText = 'Stable';
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? AppTheme.primary.withValues(alpha: 0.05) 
                                    : context.surfaceColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected 
                                      ? AppTheme.primary.withValues(alpha: 0.3) 
                                      : context.borderColor.withValues(alpha: 0.1),
                                  width: isSelected ? 1.5 : 1,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: AppTheme.primary.withValues(alpha: 0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ] : [],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() => _selectedMedicine = m),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: (isSelected ? AppTheme.primary : Colors.blueGrey).withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          Icons.medication_rounded,
                                          color: isSelected ? AppTheme.primary : Colors.blueGrey,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              m.name, 
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: context.borderColor.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                m.category.isEmpty ? "General" : m.category,
                                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                       Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${m.totalStock} ${m.unit}', 
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppTheme.indigo),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Rate: ${velocity.toStringAsFixed(1)}/d',
                                                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: timelineColor.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  timelineText,
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: timelineColor),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        // Draggable Divider Resize Handle
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _leftPaneWidth = (_leftPaneWidth + details.delta.dx).clamp(280.0, 600.0);
            });
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Container(
              width: 8,
              color: context.borderColor.withValues(alpha: 0.15),
              child: Center(
                child: Container(
                  width: 2,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.textColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Right Pane (Details View)
        Expanded(
          child: Container(
            color: context.bgColor,
            padding: const EdgeInsets.all(24),
            child: _selectedMedicine == null
                ? const Center(child: Text('Select a medicine to view details.'))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeaderSection(context, _selectedMedicine!),
                        const SizedBox(height: 24),
                        _buildKPISection(context, _selectedMedicine!, sales),
                        const SizedBox(height: 24),
                        _buildFinancialsSection(context, _selectedMedicine!),
                        const SizedBox(height: 24),
                        _buildStockSection(context, _selectedMedicine!),
                        const SizedBox(height: 24),
                        _buildBatchesSection(context, _selectedMedicine!),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSortChip(String label, String value) {
    final isSelected = _sortBy == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _sortBy = value);
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: isSelected ? AppTheme.primary : context.textColor.withValues(alpha: 0.8),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final double itemHeight = 76.0; // exact card height + margin (68 + 8)
    final double viewportHeight = _scrollController.position.viewportDimension;
    final double currentScroll = _scrollController.offset;
    
    final double itemTop = index * itemHeight;
    final double itemBottom = itemTop + itemHeight;
    
    if (itemTop < currentScroll) {
      _scrollController.animateTo(
        itemTop,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    } else if (itemBottom > currentScroll + viewportHeight) {
      _scrollController.animateTo(
        itemBottom - viewportHeight,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  void _selectNext(List<Medicine> list) {
    if (list.isEmpty) return;
    if (_selectedMedicine == null) {
      setState(() => _selectedMedicine = list.first);
      _scrollToIndex(0);
      return;
    }
    final currentIndex = list.indexWhere((m) => m.id == _selectedMedicine!.id);
    if (currentIndex != -1 && currentIndex < list.length - 1) {
      setState(() => _selectedMedicine = list[currentIndex + 1]);
      _scrollToIndex(currentIndex + 1);
    }
  }

  void _selectPrevious(List<Medicine> list) {
    if (list.isEmpty) return;
    if (_selectedMedicine == null) {
      setState(() => _selectedMedicine = list.first);
      _scrollToIndex(0);
      return;
    }
    final currentIndex = list.indexWhere((m) => m.id == _selectedMedicine!.id);
    if (currentIndex > 0) {
      setState(() => _selectedMedicine = list[currentIndex - 1]);
      _scrollToIndex(currentIndex - 1);
    }
  }

  Widget _buildHeaderSection(BuildContext context, Medicine m) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.vaccines_rounded, color: AppTheme.primary, size: 36),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.borderColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          m.category.isEmpty ? 'General' : m.category,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('Unit: ${m.unit}', style: TextStyle(color: context.textMutedColor, fontSize: 13)),
                      if (m.barcode.isNotEmpty) ...[
                        const SizedBox(width: 16),
                        Text('Barcode: ${m.barcode}', style: TextStyle(color: context.textMutedColor, fontSize: 13, fontFamily: 'monospace')),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (m.isScheduleH1)
              const AppStatusBadge(
                label: 'SCHEDULE H1 DRUG',
                color: AppTheme.danger,
                style: AppStatusBadgeStyle.text,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPISection(BuildContext context, Medicine m, List<Sale> sales) {
    final v7 = AnalyticsHelper.dailyConsumptionRate(m.id, sales, trendDays: 7);
    final v30 = AnalyticsHelper.dailyConsumptionRate(m.id, sales, trendDays: 30);
    final v90 = AnalyticsHelper.dailyConsumptionRate(m.id, sales, trendDays: 90);
    final daysLeft = AnalyticsHelper.daysOfStockRemaining(m, sales, trendDays: 30);

    String timelineLabel = 'Stable';
    Color timelineColor = Colors.green;
    if (v30 > 0) {
      if (daysLeft < 7) {
        timelineLabel = 'Critical (${daysLeft.toStringAsFixed(0)}d)';
        timelineColor = AppTheme.danger;
      } else if (daysLeft < 15) {
        timelineLabel = 'Urgent (${daysLeft.toStringAsFixed(0)}d)';
        timelineColor = AppTheme.orange;
      } else if (daysLeft < 30) {
        timelineLabel = 'Depleting (${daysLeft.toStringAsFixed(0)}d)';
        timelineColor = AppTheme.warning;
      } else {
        timelineLabel = '${(daysLeft / 30).toStringAsFixed(1)} Months';
      }
    }

    return Row(
      children: [
        Expanded(
          child: _buildKPICard('TOTAL STOCK', '${m.totalStock} ${m.unit}', Icons.inventory_rounded, AppTheme.indigo),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKPICard('DAILY VELOCITY (30d)', '${v30.toStringAsFixed(2)} / day', Icons.speed_rounded, AppTheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKPICard('ESTIMATED LIFE', timelineLabel, Icons.hourglass_empty_rounded, timelineColor),
        ),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialsSection(BuildContext context, Medicine m) {
    final markup = m.purchasePrice > 0 ? ((m.sellingPrice - m.purchasePrice) / m.purchasePrice * 100) : 0.0;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FINANCIAL ANALYSIS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildFinancialInfoBox('COST PRICE', '₹${m.purchasePrice.toStringAsFixed(2)}', Colors.orange)),
                const SizedBox(width: 16),
                Expanded(child: _buildFinancialInfoBox('SELLING PRICE', '₹${m.sellingPrice.toStringAsFixed(2)}', Colors.teal)),
                const SizedBox(width: 16),
                Expanded(child: _buildFinancialInfoBox('PROFIT MARGIN', '₹${m.profitMargin.toStringAsFixed(2)}', AppTheme.primaryLight)),
                const SizedBox(width: 16),
                Expanded(child: _buildFinancialInfoBox('MARKUP PERCENTAGE', '${markup.toStringAsFixed(1)}%', AppTheme.success)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialInfoBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildStockSection(BuildContext context, Medicine m) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('STOCK DISTRIBUTION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildDistributionTile('CLINIC COUNTER', m.mainStock, Icons.storefront_rounded, AppTheme.indigo),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDistributionTile('CLINIC BULK WAREHOUSE', m.bulkClinicStock, Icons.warehouse_rounded, Colors.deepPurple),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDistributionTile('STORE COUNTER', m.storeStock, Icons.desktop_mac_rounded, const Color(0xFF14B8A6)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDistributionTile('STORE BULK WAREHOUSE', m.bulkStoreStock, Icons.warehouse_rounded, Colors.teal),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistributionTile(String label, int quantity, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
            ],
          ),
          Text('$quantity units', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  Widget _buildBatchesSection(BuildContext context, Medicine m) {
    final now = DateTime.now();
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('REGISTERED BATCHES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5)),
            const SizedBox(height: 16),
            if (m.batches.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No batches registered.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                ),
              )
            else
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(3),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(1.5),
                },
                border: TableBorder(horizontalInside: BorderSide(color: context.borderColor.withValues(alpha: 0.1))),
                children: [
                  TableRow(
                    children: [
                      _buildTableHeader('Batch No'),
                      _buildTableHeader('Expiry Date'),
                      _buildTableHeader('Location Breakdown (Clinic | Store)'),
                      _buildTableHeader('Total Qty'),
                      _buildTableHeader('Status'),
                    ].map((w) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: w)).toList(),
                  ),
                  ...m.batches.map((b) {
                    final total = b.mainStock + b.storeStock + b.bulkClinicStock + b.bulkStoreStock;
                    final isExpired = b.expiryDate.isBefore(now);
                    final isNearExpiry = !isExpired && b.expiryDate.isBefore(now.add(const Duration(days: 90)));
                    
                    Color statusColor = Colors.green;
                    String statusLabel = 'ACTIVE';
                    if (isExpired) {
                      statusColor = AppTheme.danger;
                      statusLabel = 'EXPIRED';
                    } else if (isNearExpiry) {
                      statusColor = AppTheme.orange;
                      statusLabel = 'NEAR EXPIRY';
                    }

                    return TableRow(
                      children: [
                        Text(b.batchNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(DateFormat('dd/MM/yyyy').format(b.expiryDate), style: const TextStyle(fontSize: 13)),
                        Text(
                          'C: ${b.mainStock} (Bulk: ${b.bulkClinicStock}) | S: ${b.storeStock} (Bulk: ${b.bulkStoreStock})',
                          style: TextStyle(color: context.textMutedColor, fontSize: 12),
                        ),
                        Text('$total ${m.unit}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ].map((w) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: w)).toList(),
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey));
  }
}
