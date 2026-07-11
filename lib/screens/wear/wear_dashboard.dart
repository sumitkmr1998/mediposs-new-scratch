import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/services/sync_service.dart';
import '../../theme/app_theme.dart';

class WearDashboard extends StatefulWidget {
  const WearDashboard({super.key});

  @override
  State<WearDashboard> createState() => _WearDashboardState();
}

class _WearDashboardState extends State<WearDashboard> {
  bool _isSyncing = false;

  Future<void> _refreshData() async {
    setState(() => _isSyncing = true);
    try {
      final salesProv = context.read<SalesProvider>();
      salesProv.load();
      // Trigger sync pull if possible
      final syncService = SyncService.instance;
      await syncService.pullSales();
      salesProv.load();
    } catch (e) {
      debugPrint('WearDashboard Sync Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    const isRound = true;
    const isAmbient = false;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Consumer<SalesProvider>(
                builder: (context, salesProv, child) {
                  // Calculate today's sales
                  final now = DateTime.now();
                  final startOfDay = DateTime(now.year, now.month, now.day);
                  final todaySales = salesProv.sales.where((s) {
                    final date = s.createdAt;
                    return date.isAfter(startOfDay) || date.isAtSameMomentAs(startOfDay);
                  }).toList();

                  double totalRevenue = 0;
                  double clinicSales = 0;
                  double storeSales = 0;
                  int txCount = todaySales.length;

                  for (var s in todaySales) {
                    totalRevenue += s.total;
                    if (s.invoiceNo.startsWith('OPD-') || s.linkedAppointmentId != null) {
                      clinicSales += s.total;
                    } else {
                      storeSales += s.total;
                    }
                  }

                  final formatCurrency = NumberFormat.simpleCurrency(decimalDigits: 0, locale: 'en_IN');

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'TODAY\'S REVENUE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: AppTheme.primaryLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCurrency.format(totalRevenue),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$txCount Transactions',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMiniStat(
                              'STORE', 
                              formatCurrency.format(storeSales), 
                              isAmbient,
                            ),
                            Container(
                              height: 16,
                              width: 1,
                              color: Colors.white24,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            _buildMiniStat(
                              'CLINIC', 
                              formatCurrency.format(clinicSales), 
                              isAmbient,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _isSyncing ? null : _refreshData,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: _isSyncing
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, bool isAmbient) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            color: isAmbient ? Colors.grey : AppTheme.primaryLight.withAlpha(200),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
