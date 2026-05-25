import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../shared/models/medicine.dart';
import '../../shared/models/procedure.dart';
import '../../shared/models/sale.dart';
import '../../shared/models/stock_transfer.dart';
import '../../shared/services/objectbox_service.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/procedure_provider.dart';
import '../../shared/utils/analytics_helper.dart';
import '../../theme/app_theme.dart';

class AnalysisHubScreen extends StatefulWidget {
  const AnalysisHubScreen({super.key});

  @override
  State<AnalysisHubScreen> createState() => _AnalysisHubScreenState();
}

class _AnalysisHubScreenState extends State<AnalysisHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _period = 'This Month';
  
  // State for detailed performance view (Medicines & Procedures)
  Medicine? _selectedMedicine;
  Procedure? _selectedProcedure;
  bool _showProcedures = false;
  String _clinicSearchQuery = '';
  
  String _detailPeriod = 'Last 30 Days';
  DateTimeRange? _detailCustomRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();
    final salesProvider = context.watch<SalesProvider>();
    final patientProvider = context.watch<PatientProvider>();
    final procedureProvider = context.watch<ProcedureProvider>();

    final allMedicines = inventory.rawMedicines;
    final allSales = salesProvider.rawSales;
    final allPatients = patientProvider.patients;
    final allProcedures = procedureProvider.procedures;

    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        title: const Text('💡 Advanced Business Analytics'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: context.textMutedColor,
          tabs: const [
            Tab(icon: Icon(Icons.analytics_rounded), text: 'Sales Trends'),
            Tab(icon: Icon(Icons.pie_chart_rounded), text: 'Category Sales Weight'),
            Tab(icon: Icon(Icons.bar_chart_rounded), text: 'Performance Explorer'),
            Tab(icon: Icon(Icons.warning_amber_rounded), text: 'Reorder & Dead Stock'),
            Tab(icon: Icon(Icons.people_rounded), text: 'Patient Analytics'),
            Tab(icon: Icon(Icons.compare_arrows_rounded), text: 'Clinic Reconciliation'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSalesTrendsTab(allSales, allMedicines),
          _buildCategorySalesTab(allSales, allMedicines),
          _buildProductPerformanceTab(allSales, allMedicines, allProcedures),
          _buildReorderAndDeadStockTab(allSales, allMedicines),
          _buildPatientAnalyticsTab(allSales, allPatients),
          _buildClinicReconciliationTab(allSales, allMedicines),
        ],
      ),
    );
  }

  // ==========================================
  // 1. SALES TRENDS TAB
  // ==========================================
  Widget _buildSalesTrendsTab(List<Sale> sales, List<Medicine> medicines) {
    final now = DateTime.now();
    late DateTime start;

    if (_period == 'This Week') {
      start = now.subtract(Duration(days: now.weekday - 1));
    } else if (_period == 'This Month') {
      start = DateTime(now.year, now.month, 1);
    } else {
      start = DateTime(now.year, now.month - 3, 1);
    }

    final filteredSales = sales.where((s) => s.createdAt.isAfter(start)).toList();
    final revenueData = AnalyticsHelper.aggregateDailyRevenue(filteredSales);
    final profitData = AnalyticsHelper.aggregateDailyProfit(filteredSales, medicines);

    double totalRevenue = filteredSales.where((s) => !s.isReturn).fold(0.0, (sum, s) => sum + s.total);
    double totalReturns = filteredSales.where((s) => s.isReturn).fold(0.0, (sum, s) => sum + s.total);
    double netRevenue = totalRevenue - totalReturns;
    
    double netProfit = 0.0;
    profitData.forEach((_, val) => netProfit += val);

    final marginPercent = netRevenue > 0 ? (netProfit / netRevenue) * 100 : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Financial Overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Row(
                children: ['This Week', 'This Month', 'Last 3 Months'].map((p) {
                  final isSelected = p == _period;
                  return Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(p),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _period = p),
                      selectedColor: AppTheme.primary.withOpacity(0.2),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard('Gross Revenue', '₹${totalRevenue.toStringAsFixed(2)}', Icons.payments_rounded, AppTheme.indigo),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard('Net Profits', '₹${netProfit.toStringAsFixed(2)}', Icons.trending_up_rounded, AppTheme.success),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard('Net Margin', '${marginPercent.toStringAsFixed(1)}%', Icons.percent_rounded, AppTheme.accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard('Returns Logged', '₹${totalReturns.toStringAsFixed(2)}', Icons.keyboard_return_rounded, AppTheme.danger),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Net Revenue & Profit Curve',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                height: 320,
                child: revenueData.isEmpty
                    ? const Center(child: Text('No transaction logs available for this period.'))
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: (revenueData.keys.length / 5).clamp(1.0, 30.0),
                                getTitlesWidget: (value, _) {
                                  final sorted = revenueData.keys.toList()..sort();
                                  final idx = value.toInt();
                                  if (idx >= 0 && idx < sorted.length) {
                                    final d = sorted[idx];
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 10)),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: revenueData.keys.toList().asMap().entries.map((e) {
                                final date = e.value;
                                return FlSpot(e.key.toDouble(), revenueData[date] ?? 0.0);
                              }).toList(),
                              isCurved: true,
                              color: AppTheme.indigo,
                              barWidth: 3,
                              belowBarData: BarAreaData(show: true, color: AppTheme.indigo.withOpacity(0.08)),
                              dotData: const FlDotData(show: false),
                            ),
                            LineChartBarData(
                              spots: profitData.keys.toList().asMap().entries.map((e) {
                                final date = e.value;
                                return FlSpot(e.key.toDouble(), profitData[date] ?? 0.0);
                              }).toList(),
                              isCurved: true,
                              color: AppTheme.success,
                              barWidth: 3,
                              belowBarData: BarAreaData(show: true, color: AppTheme.success.withOpacity(0.08)),
                              dotData: const FlDotData(show: false),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIndicator(AppTheme.indigo, 'Net Sales'),
              const SizedBox(width: 24),
              _buildIndicator(AppTheme.success, 'Profit'),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 2. CATEGORY SALES TAB
  // ==========================================
  Widget _buildCategorySalesTab(List<Sale> sales, List<Medicine> medicines) {
    final catSales = AnalyticsHelper.getCategorySales(sales, medicines);
    final sortedCats = catSales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    double totalRevenue = catSales.values.fold(0.0, (sum, val) => sum + val);

    final List<Color> donutColors = [
      AppTheme.primary,
      AppTheme.indigo,
      AppTheme.purple,
      AppTheme.sky,
      AppTheme.orange,
      AppTheme.accent,
      AppTheme.teal,
      Colors.pinkAccent,
      Colors.lightGreen,
    ];

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category Sales Weight', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  Expanded(
                    child: catSales.isEmpty
                        ? const Center(child: Text('No categories with sales records.'))
                        : PieChart(
                            PieChartData(
                              sectionsSpace: 3,
                              centerSpaceRadius: 60,
                              sections: List.generate(sortedCats.length, (i) {
                                final entry = sortedCats[i];
                                final percentage = totalRevenue > 0 ? (entry.value / totalRevenue) * 100 : 0.0;
                                return PieChartSectionData(
                                  color: donutColors[i % donutColors.length],
                                  value: entry.value,
                                  title: '${percentage.toStringAsFixed(0)}%',
                                  radius: 40,
                                  titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                );
                              }),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ranked Category Yield', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.separated(
                      itemCount: sortedCats.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, idx) {
                        final entry = sortedCats[idx];
                        final percentage = totalRevenue > 0 ? (entry.value / totalRevenue) * 100 : 0.0;
                        final color = donutColors[idx % donutColors.length];

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text('₹${entry.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 16),
                              Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(color: context.textMutedColor, fontSize: 13)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // ==========================================
  // 3. PERFORMANCE EXPLORER TAB (Medicines & Procedures)
  // ==========================================
  Widget _buildProductPerformanceTab(List<Sale> sales, List<Medicine> medicines, List<Procedure> procedures) {
    if (_selectedMedicine != null || _selectedProcedure != null) {
      return _buildDetailView(
        sales: sales,
        medicine: _selectedMedicine,
        procedure: _selectedProcedure,
      );
    }

    final performanceList = AnalyticsHelper.getMedicinePerformanceLeaderboard(medicines, sales);

    // Computing procedure performance list
    final procedurePerformanceList = <ProcedurePerformance>[];
    if (_showProcedures) {
      final performanceMap = <int, int>{};
      final revenueMap = <int, double>{};

      for (final sale in sales) {
        if (sale.isReturn) continue;
        for (final item in AnalyticsHelper.getItems(sale)) {
          if (item.isProcedure) {
            performanceMap[item.procedureId] = (performanceMap[item.procedureId] ?? 0) + item.qty;
            revenueMap[item.procedureId] = (revenueMap[item.procedureId] ?? 0.0) + item.lineTotal;
          }
        }
      }

      for (final p in procedures) {
        final units = performanceMap[p.id] ?? 0;
        final rev = revenueMap[p.id] ?? 0.0;
        procedurePerformanceList.add(ProcedurePerformance(
          procedure: p,
          unitsSold: units,
          revenue: rev,
          profit: rev, // 100% margin on procedures
        ));
      }
      procedurePerformanceList.sort((a, b) => b.unitsSold.compareTo(a.unitsSold));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Segmented Button or Toggle between Medicines and Procedures
              ToggleButtons(
                borderRadius: BorderRadius.circular(12),
                selectedColor: Colors.white,
                fillColor: AppTheme.primary,
                color: context.textMutedColor,
                constraints: const BoxConstraints(minHeight: 40, minWidth: 150),
                isSelected: [!_showProcedures, _showProcedures],
                onPressed: (index) {
                  setState(() {
                    _showProcedures = index == 1;
                  });
                },
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Medicines', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Clinical Services', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Spacer(),
              // Search autocomplete
              SizedBox(
                width: 400,
                child: _showProcedures
                    ? Autocomplete<Procedure>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Procedure>.empty();
                          }
                          return procedures.where((p) =>
                              p.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                              p.category.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                        },
                        displayStringForOption: (Procedure p) => p.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search clinical service to view stats...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        controller.clear();
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                        onSelected: (Procedure p) {
                          setState(() {
                            _selectedProcedure = p;
                          });
                        },
                      )
                    : Autocomplete<Medicine>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Medicine>.empty();
                          }
                          return medicines.where((m) =>
                              m.name.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                              m.barcode.contains(textEditingValue.text));
                        },
                        displayStringForOption: (Medicine m) => m.name,
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Search medicine to view detailed stats...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        controller.clear();
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                        onSelected: (Medicine m) {
                          setState(() {
                            _selectedMedicine = m;
                          });
                        },
                      ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _showProcedures
                    ? (procedurePerformanceList.isEmpty
                        ? const Center(child: Text('No clinical services sales logs detected.'))
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 3, child: Text('Service Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 2, child: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('Sessions Conducted', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('Revenue Generated', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('Net Profit (100%)', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 48),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: procedurePerformanceList.length,
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemBuilder: (context, index) {
                                    final perf = procedurePerformanceList[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Text(perf.procedure.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(perf.procedure.category),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('${perf.unitsSold} sessions'),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.revenue.toStringAsFixed(0)}'),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.profit.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.bar_chart_rounded, color: AppTheme.primary),
                                        onPressed: () {
                                          setState(() {
                                            _selectedProcedure = perf.procedure;
                                          });
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ))
                    : (performanceList.isEmpty
                        ? const Center(child: Text('No product sales logs detected.'))
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 3, child: Text('Medicine Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 2, child: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('Units Sold', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('Revenue', style: TextStyle(fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('Gross Profit', style: TextStyle(fontWeight: FontWeight.bold))),
                                    SizedBox(width: 48),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: performanceList.length,
                                  separatorBuilder: (_, __) => const Divider(),
                                  itemBuilder: (context, index) {
                                    final perf = performanceList[index];
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Text(perf.medicine.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(perf.medicine.category),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('${perf.unitsSold} ${perf.medicine.unit}'),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.revenue.toStringAsFixed(0)}'),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text('₹${perf.profit.toStringAsFixed(0)}', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.bar_chart_rounded, color: AppTheme.primary),
                                        onPressed: () {
                                          setState(() {
                                            _selectedMedicine = perf.medicine;
                                          });
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Unified deep-dive details view supporting medicines and clinical services
  Widget _buildDetailView({
    required List<Sale> sales,
    Medicine? medicine,
    Procedure? procedure,
  }) {
    final String name = medicine?.name ?? procedure?.name ?? 'Unknown';
    final String category = medicine?.category ?? procedure?.category ?? 'General';
    final String unit = medicine?.unit ?? 'sessions';
    final double purchasePrice = medicine?.purchasePrice ?? 0.0;
    final double sellingPrice = medicine?.sellingPrice ?? procedure?.basePrice ?? 0.0;
    final int totalStock = medicine?.totalStock ?? 0;
    final double marginPercent = sellingPrice > 0 ? (((sellingPrice - purchasePrice) / sellingPrice) * 100) : 0.0;

    final now = DateTime.now();
    DateTime start = now.subtract(const Duration(days: 30));
    DateTime end = now;

    if (_detailPeriod == 'This Month') {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_detailPeriod == 'Last Month') {
      start = DateTime(now.year, now.month - 1, 1);
      end = DateTime(now.year, now.month, 0, 23, 59, 59);
    } else if (_detailPeriod == 'Last 3 Months') {
      start = DateTime(now.year, now.month - 3, 1);
      end = now;
    } else if (_detailPeriod == 'Custom Range' && _detailCustomRange != null) {
      start = _detailCustomRange!.start;
      end = _detailCustomRange!.end;
    }

    final filteredSales = sales.where((s) {
      if (s.isReturn) return false;
      return s.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
             s.createdAt.isBefore(end.add(const Duration(seconds: 1)));
    }).toList();

    int totalSold = 0;
    double revenue = 0.0;
    final dailySales = <DateTime, int>{};
    final List<SaleRow> invoiceDetails = [];
    final patientVisitCount = <String, int>{};

    for (final sale in filteredSales) {
      final items = AnalyticsHelper.getItems(sale);
      for (final item in items) {
        final isMatch = (medicine != null && !item.isProcedure && item.medicineId == medicine.id) ||
                        (procedure != null && item.isProcedure && item.procedureId == procedure.id);
        if (isMatch) {
          totalSold += item.qty;
          revenue += item.lineTotal;
          final day = DateTime(sale.createdAt.year, sale.createdAt.month, sale.createdAt.day);
          dailySales[day] = (dailySales[day] ?? 0) + item.qty;
          invoiceDetails.add(
            SaleRow(
              date: sale.createdAt,
              invoiceNo: sale.invoiceNo,
              customer: sale.patientName.isNotEmpty ? sale.patientName : 'Walk-in Customer',
              qty: item.qty,
              total: item.lineTotal,
            ),
          );

          if (procedure != null) {
            final patientName = sale.patientName.isNotEmpty ? sale.patientName : 'Walk-in Customer';
            patientVisitCount[patientName] = (patientVisitCount[patientName] ?? 0) + item.qty;
          }
        }
      }
    }

    final int daysCount = end.difference(start).inDays.clamp(1, 99999);
    final dailyAvg = totalSold / daysCount.toDouble();
    
    double daysLeft = 999.0;
    if (medicine != null) {
      final dailyConsumption = AnalyticsHelper.dailyConsumptionRate(medicine.id, sales);
      daysLeft = dailyConsumption <= 0 ? 999.0 : medicine.totalStock / dailyConsumption;
    }
    
    final profit = revenue - (purchasePrice * totalSold);
    final sortedPatients = patientVisitCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final DateFormat formatter = DateFormat('dd MMM yyyy');
    final String rangeText = _detailPeriod == 'Custom Range' && _detailCustomRange != null
        ? '${formatter.format(_detailCustomRange!.start)} - ${formatter.format(_detailCustomRange!.end)}'
        : '${formatter.format(start)} - ${formatter.format(end)}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() {
              _selectedMedicine = null;
              _selectedProcedure = null;
              _detailPeriod = 'Last 30 Days';
              _detailCustomRange = null;
            });
          },
        ),
        title: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name Performance Metrics', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(rangeText, style: TextStyle(color: context.textMutedColor, fontSize: 12, fontWeight: FontWeight.normal)),
              ],
            ),
            const Spacer(),
            Row(
              children: ['Last 30 Days', 'This Month', 'Last Month', 'Last 3 Months', 'Custom Range'].map((p) {
                final isSelected = p == _detailPeriod;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(p),
                    selected: isSelected,
                    onSelected: (selected) async {
                      if (selected) {
                        if (p == 'Custom Range') {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 1),
                            initialDateRange: _detailCustomRange ?? DateTimeRange(
                              start: now.subtract(const Duration(days: 30)),
                              end: now,
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              _detailPeriod = p;
                              _detailCustomRange = picked;
                            });
                          }
                        } else {
                          setState(() {
                            _detailPeriod = p;
                          });
                        }
                      }
                    },
                    selectedColor: AppTheme.primary.withOpacity(0.2),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (medicine != null) _buildMedicineAlerts(medicine, daysLeft),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.25,
                  children: [
                    _buildMetricCard('Revenue', '₹${revenue.toStringAsFixed(0)}', Icons.payments_rounded, AppTheme.indigo),
                    _buildMetricCard('Gross Profit', '₹${profit.toStringAsFixed(0)}', Icons.trending_up_rounded, AppTheme.success),
                    _buildMetricCard(medicine != null ? 'Units Sold' : 'Sessions Conducted', '$totalSold', Icons.shopping_bag_rounded, AppTheme.primary),
                    _buildMetricCard('Daily Avg', dailyAvg.toStringAsFixed(1), Icons.show_chart_rounded, Colors.orange),
                    _buildMetricCard(
                      medicine != null ? 'Total Stock' : 'Type',
                      medicine != null ? '$totalStock' : 'Clinical Service',
                      Icons.inventory_2_rounded,
                      AppTheme.teal,
                    ),
                    _buildMetricCard(
                      medicine != null ? 'Stock Life' : 'Profit Margin',
                      medicine != null ? (daysLeft >= 999.0 ? '∞' : '${daysLeft.toStringAsFixed(0)} Days') : '100%',
                      Icons.timer_rounded,
                      medicine != null ? (daysLeft < 14 ? AppTheme.danger : AppTheme.success) : AppTheme.success,
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Quantity Sold Trend' : 'Sessions Booked Trend', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: Container(
                              height: 280,
                              padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                              child: dailySales.isEmpty
                                  ? const Center(child: Text('No sales registered in selected period.'))
                                  : _buildMiniSalesTrendChart(dailySales),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Inventory Configuration' : 'Clinical Service Configuration', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: medicine != null
                                  ? Column(
                                      children: [
                                        _buildStockFieldRow('Store Front Stock', '${medicine.storeStock} ${medicine.unit}', Icons.store),
                                        const Divider(),
                                        _buildStockFieldRow('Warehouse Stock', '${medicine.mainStock} ${medicine.unit}', Icons.warehouse),
                                        const Divider(),
                                        _buildStockFieldRow('Purchase Cost', '₹${medicine.purchasePrice.toStringAsFixed(2)}', Icons.shopping_cart),
                                        const Divider(),
                                        _buildStockFieldRow('Selling Price', '₹${medicine.sellingPrice.toStringAsFixed(2)}', Icons.sell),
                                        const Divider(),
                                        _buildStockFieldRow('Margin Percent', '${marginPercent.toStringAsFixed(1)}%', Icons.percent),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildStockFieldRow('Service Category', category, Icons.category_rounded),
                                        const Divider(),
                                        _buildStockFieldRow('Standard Base Price', '₹${sellingPrice.toStringAsFixed(2)}', Icons.sell),
                                        const Divider(),
                                        _buildStockFieldRow('Net Profit Margin', '100% (No purchase cost)', Icons.percent_rounded),
                                        const Divider(),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.description_rounded, size: 20, color: AppTheme.primary),
                                                  const SizedBox(width: 16),
                                                  Text('Description', style: TextStyle(fontWeight: FontWeight.w500, color: context.textMutedColor)),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                procedure!.description.isNotEmpty ? procedure.description : 'Professional clinical procedure service.',
                                                style: const TextStyle(fontSize: 13, height: 1.4),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(medicine != null ? 'Batch Listings' : 'Top Patient Consumers', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          if (medicine != null) ...[
                            if (medicine.batches.isEmpty)
                              const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No active batches defined.'))))
                            else
                              ...medicine.batches.map((b) => _buildMiniBatchCard(b)),
                          ] else ...[
                            Card(
                              child: sortedPatients.isEmpty
                                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No clinical history for this service in this period.')))
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: sortedPatients.length.clamp(0, 5),
                                      separatorBuilder: (_, __) => const Divider(),
                                      itemBuilder: (context, index) {
                                        final entry = sortedPatients[index];
                                        return ListTile(
                                          leading: CircleAvatar(
                                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                                            child: Text('${index + 1}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                          ),
                                          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          subtitle: const Text('Recipient patient'),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                            child: Text('${entry.value} $unit', style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 12)),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ]
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Recent Invoices', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Card(
                            child: invoiceDetails.isEmpty
                                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No invoice registers in selected period.')))
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: invoiceDetails.length.clamp(0, 5),
                                    separatorBuilder: (_, __) => const Divider(),
                                    itemBuilder: (context, index) {
                                      final row = invoiceDetails[invoiceDetails.length - 1 - index];
                                      return ListTile(
                                        title: Text(row.customer, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text('${row.invoiceNo} • ${DateFormat('dd MMM yyyy').format(row.date)}'),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text('₹${row.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                            Text('${row.qty} $unit', style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicineAlerts(Medicine m, double daysLeft) {
    final alerts = <Widget>[];

    if (m.hasExpiredBatch) {
      alerts.add(_buildStatusWarningCard('Expired Batches Detected!', 'Some batches are past their expiry date. Remove them immediately.', AppTheme.danger));
    } else if (m.hasNearExpiryBatch) {
      alerts.add(_buildStatusWarningCard('Near Expiry Batch Present', 'Stock batches are expiring soon. Consider prioritizing sales.', Colors.orange));
    }

    if (daysLeft < 14 && daysLeft < 999.0) {
      alerts.add(_buildStatusWarningCard('Stock Out Depletion Alert!', 'Current stock level will deplete within approximately ${daysLeft.toStringAsFixed(0)} days.', AppTheme.danger));
    }

    if (alerts.isEmpty) return const SizedBox();
    return Column(children: alerts);
  }

  Widget _buildStatusWarningCard(String title, String desc, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
              Text(desc, style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockFieldRow(String label, String val, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMiniBatchCard(MedicineBatch b) {
    final isExp = b.expiryDate.isBefore(DateTime.now());
    final isNear = b.expiryDate.isBefore(DateTime.now().add(const Duration(days: 90))) && !isExp;
    final color = isExp ? AppTheme.danger : isNear ? Colors.orange : AppTheme.success;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('Batch: ${b.batchNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(
                  isExp ? 'EXPIRED' : isNear ? 'NEAR EXP' : 'HEALTHY',
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniBatchField('Store', '${b.storeStock}'),
              _buildMiniBatchField('Warehouse', '${b.mainStock}'),
              _buildMiniBatchField('Expiry', DateFormat('dd/MM/yyyy').format(b.expiryDate)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBatchField(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textMutedColor, fontSize: 10)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMiniSalesTrendChart(Map<DateTime, int> dailySales) {
    final sortedDates = dailySales.keys.toList()..sort();
    final spots = List.generate(sortedDates.length, (i) {
      final date = sortedDates[i];
      return FlSpot(i.toDouble(), dailySales[date]!.toDouble());
    });

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (sortedDates.length / 5).clamp(1.0, 30.0),
              getTitlesWidget: (value, _) {
                final idx = value.toInt();
                if (idx >= 0 && idx < sortedDates.length) {
                  final d = sortedDates[idx];
                  return Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 9));
                }
                return const Text('');
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.primary,
            barWidth: 3,
            belowBarData: BarAreaData(show: true, color: AppTheme.primary.withOpacity(0.08)),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 4. REORDERS & DEAD STOCK TAB
  // ==========================================
  Widget _buildReorderAndDeadStockTab(List<Sale> sales, List<Medicine> medicines) {
    final reorders = AnalyticsHelper.getReorderList(medicines, sales);
    final deadStock = AnalyticsHelper.getDeadStock(medicines, sales, 60); // 60 days dead stock default

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🚨 Urgent Reorder Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text('${reorders.length} Items', style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: reorders.isEmpty
                        ? const Center(child: Text('All stock levels are completely healthy.'))
                        : ListView.separated(
                            itemCount: reorders.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, idx) {
                              final rec = reorders[idx];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(rec.medicine.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Stock: ${rec.medicine.totalStock} • Low Limit: ${rec.medicine.lowStockThreshold}'),
                                trailing: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Suggest: +${rec.suggestedReorderQty}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                    Text(
                                      rec.daysLeft >= 999.0 ? 'Stock Life: ∞' : 'Life: ${rec.daysLeft.toStringAsFixed(0)}d',
                                      style: TextStyle(color: rec.daysLeft < 7 ? AppTheme.danger : context.textMutedColor, fontSize: 11),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 24, 24, 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('⚠️ Sluggish / Dead Stock (60 Days)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text('${deadStock.length} Items', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: deadStock.isEmpty
                        ? const Center(child: Text('No slow-moving stocks detected.'))
                        : ListView.separated(
                            itemCount: deadStock.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, idx) {
                              final med = deadStock[idx];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(med.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Category: ${med.category} • Barcode: ${med.barcode}'),
                                trailing: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('${med.totalStock} ${med.unit} left', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text('Value: ₹${(med.totalStock * med.purchasePrice).toStringAsFixed(0)}', style: TextStyle(color: context.textMutedColor, fontSize: 11)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // 5. PATIENT ANALYTICS TAB
  // ==========================================
  Widget _buildPatientAnalyticsTab(List<Sale> sales, List patients) {
    // Check patient provider structure
    final patientProviderList = Provider.of<PatientProvider>(context, listen: false).patients;
    final stats = AnalyticsHelper.getPatientAnalytics(sales, patientProviderList);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Patient Engagement Metrics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildMetricCard('Total Invoices', '${sales.length}', Icons.description_rounded, AppTheme.indigo)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard('Patients Served', '${stats.uniquePatientsServed}', Icons.people_rounded, AppTheme.sky)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard('Repeat Rate', '${stats.repeatPatientRate.toStringAsFixed(1)}%', Icons.replay_rounded, AppTheme.success)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricCard('Avg Checkout Ticket', '₹${stats.averageBasketValue.toStringAsFixed(2)}', Icons.shopping_basket_rounded, AppTheme.accent)),
            ],
          ),
          const SizedBox(height: 32),
          const Text('Patient Visit Frequency by Hour', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                height: 240,
                child: stats.hourlyActivity.isEmpty
                    ? const Center(child: Text('No hourly visit logs available.'))
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, _) {
                                  final h = value.toInt();
                                  if (h >= 0 && h < 24) {
                                    return Text('${h}h', style: const TextStyle(fontSize: 10));
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          barGroups: List.generate(24, (i) {
                            return BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: (stats.hourlyActivity[i] ?? 0).toDouble(),
                                  color: AppTheme.sky,
                                  width: 10,
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), topRight: Radius.circular(3)),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Common card widget
  Widget _buildMetricCard(String label, String val, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(color: context.textMutedColor, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              val,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  Widget _buildClinicReconciliationTab(List<Sale> sales, List<Medicine> medicines) {
    final allTransfers = ObjectBoxService.instance.transferBox.getAll();

    // Map of medicineId -> totalTransferred (to main)
    final transferMap = <int, int>{};
    for (final transfer in allTransfers) {
      if (transfer.toWarehouse == 'main') {
        transferMap[transfer.medicineId] = (transferMap[transfer.medicineId] ?? 0) + transfer.qty;
      }
      if (transfer.fromWarehouse == 'main') {
        transferMap[transfer.medicineId] = (transferMap[transfer.medicineId] ?? 0) - transfer.qty;
      }
    }

    // Map of medicineId -> totalConsumed (clinical dispenses)
    final consumeMap = <int, int>{};
    for (final sale in sales) {
      if (sale.isClinicalDispense) {
        for (final item in AnalyticsHelper.getItems(sale)) {
          if (!item.isProcedure) {
            consumeMap[item.medicineId] = (consumeMap[item.medicineId] ?? 0) + item.qty;
          }
        }
      }
    }

    final relevantMedicineIds = <int>{};
    for (final mId in transferMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final mId in consumeMap.keys) {
      relevantMedicineIds.add(mId);
    }
    for (final med in medicines) {
      if (med.mainStock > 0) {
        relevantMedicineIds.add(med.id);
      }
    }

    final reconciliationRows = <_ClinicReconciliationRow>[];
    for (final mId in relevantMedicineIds) {
      final med = medicines.firstWhere((m) => m.id == mId, orElse: () => Medicine(
        name: 'Unknown Medicine (ID: $mId)',
        purchasePrice: 0,
        sellingPrice: 0,
      )..id = mId);

      final totalTransferred = transferMap[mId] ?? 0;
      final totalConsumed = consumeMap[mId] ?? 0;
      final currentStock = med.mainStock;
      final expectedStock = totalTransferred - totalConsumed;
      final variance = currentStock - expectedStock;

      if (_clinicSearchQuery.isNotEmpty && !med.name.toLowerCase().contains(_clinicSearchQuery.toLowerCase())) {
        continue;
      }

      reconciliationRows.add(_ClinicReconciliationRow(
        medicineId: mId,
        medicineName: med.name,
        totalTransferred: totalTransferred,
        totalConsumed: totalConsumed,
        currentStock: currentStock,
        variance: variance,
      ));
    }

    // Sort by largest absolute variance first, then alphabetically
    reconciliationRows.sort((a, b) {
      final vComp = b.variance.abs().compareTo(a.variance.abs());
      if (vComp != 0) return vComp;
      return a.medicineName.compareTo(b.medicineName);
    });

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clinic Stock Reconciliation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tracks stock transferred from store warehouse vs clinical dispense internal consumption.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _clinicSearchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search clinic medicine...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text('Medicine Name', style: TextStyle(fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Text('Total Transferred (In)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Total Consumed (Out)', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Current Clinic Stock', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text('Variance', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: reconciliationRows.isEmpty
                          ? const Center(child: Text('No clinic medicines or transaction data found.'))
                          : ListView.separated(
                              itemCount: reconciliationRows.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final row = reconciliationRows[index];

                                Color varianceColor = Colors.grey;
                                IconData? varianceIcon;
                                if (row.variance < 0) {
                                  varianceColor = AppTheme.danger;
                                  varianceIcon = Icons.warning_amber_rounded;
                                } else if (row.variance > 0) {
                                  varianceColor = AppTheme.success;
                                  varianceIcon = Icons.add_circle_outline_rounded;
                                }

                                final varianceText = row.variance > 0 ? '+${row.variance}' : '${row.variance}';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(row.medicineName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.totalTransferred}', textAlign: TextAlign.center),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.totalConsumed}', textAlign: TextAlign.center),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('${row.currentStock}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (varianceIcon != null) ...[
                                              Icon(varianceIcon, size: 16, color: varianceColor),
                                              const SizedBox(width: 4),
                                            ],
                                            Text(
                                              varianceText,
                                              style: TextStyle(
                                                color: varianceColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SaleRow {
  final DateTime date;
  final String invoiceNo;
  final String customer;
  final int qty;
  final double total;

  SaleRow({
    required this.date,
    required this.invoiceNo,
    required this.customer,
    required this.qty,
    required this.total,
  });
}

class ProcedurePerformance {
  final Procedure procedure;
  final int unitsSold;
  final double revenue;
  final double profit;

  ProcedurePerformance({
    required this.procedure,
    required this.unitsSold,
    required this.revenue,
    required this.profit,
  });
}

class _ClinicReconciliationRow {
  final int medicineId;
  final String medicineName;
  final int totalTransferred;
  final int totalConsumed;
  final int currentStock;
  final int variance;

  _ClinicReconciliationRow({
    required this.medicineId,
    required this.medicineName,
    required this.totalTransferred,
    required this.totalConsumed,
    required this.currentStock,
    required this.variance,
  });
}
