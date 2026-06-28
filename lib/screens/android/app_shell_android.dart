import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/services/objectbox_service.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../shared/services/local_server_service.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/services/discovery_service.dart';
import '../../shared/services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shop_selection_dialog.dart';
import '../dashboard_screen.dart';
import '../pos_screen.dart';
import '../warehouse_screen.dart';
import '../sales_history_screen.dart';
import '../settings_screen.dart';
import '../user_management_screen.dart';
import '../opd/opd_queue_screen.dart';
import '../opd/patient_list_screen.dart';
import '../opd/doctor_list_screen.dart';
import '../opd/opd_report_screen.dart';
import '../connection_screen.dart';
import '../audit_logs_screen.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/providers/prescription_provider.dart';
import '../../shared/providers/template_provider.dart';
import '../../shared/widgets/interactive_hover.dart';
import 'opd/remote_camera_screen_android.dart';
import 'package:flutter/services.dart';
import '../../shared/providers/navigation_provider.dart';
import '../../shared/widgets/connectivity_overlay.dart';
import 'dart:async';
import 'analysis_hub_android.dart';
import '../../shared/services/ota_update_service.dart';

class AppShellAndroid extends StatefulWidget {
  const AppShellAndroid({super.key});

  @override
  State<AppShellAndroid> createState() => _AppShellAndroidState();
}

class _AppShellAndroidState extends State<AppShellAndroid> {
  int _selectedIndex = 0;
  DateTime? _lastBackPress;
  Timer? _hubCheckTimer;
  bool _isHubBackOnline = false;

  @override
  void dispose() {
    _hubCheckTimer?.cancel();
    super.dispose();
  }

  List<_Dest> _buildDestinations(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final List<_Dest> dests = [];

    if (auth.canViewDashboard) {
      dests.add(const _Dest(
          id: 'dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Dashboard'));
    }

    if (auth.canViewAnalytics) {
      dests.add(const _Dest(
          id: 'analysis',
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics,
          label: 'Analysis'));
    }

    if (auth.canAccessPOS) {
      dests.add(const _Dest(
          id: 'pos',
          icon: Icons.point_of_sale_outlined,
          selectedIcon: Icons.point_of_sale,
          label: 'POS'));
    }

    if (auth.canViewWarehouse) {
      dests.add(const _Dest(
          id: 'warehouse',
          icon: Icons.warehouse_outlined,
          selectedIcon: Icons.warehouse,
          label: 'Warehouse'));
    }

    if (auth.canViewSalesHistory) {
      dests.add(const _Dest(
          id: 'sales',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          label: 'Sales'));
    }

    // OPD Section
    if (auth.canAccessOPD) {
      dests.add(const _Dest(
          id: 'opd_queue',
          icon: Icons.queue_outlined,
          selectedIcon: Icons.queue,
          label: 'OPD Queue'));
      dests.add(const _Dest(
          id: 'patients',
          icon: Icons.people_alt_outlined,
          selectedIcon: Icons.people_alt,
          label: 'Patients'));
    }

    if (auth.canViewOpdReports) {
      dests.add(const _Dest(
          id: 'opd_report',
          icon: Icons.bar_chart_outlined,
          selectedIcon: Icons.bar_chart,
          label: 'OPD Report'));
    }

    if (auth.canAccessSettings) {
      dests.add(const _Dest(
          id: 'settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: 'Settings'));
    }

    if (auth.isAdmin || auth.currentUser?.role.toLowerCase() == 'manager') {
      dests.add(const _Dest(
          id: 'audit_logs',
          icon: Icons.history_toggle_off_rounded,
          selectedIcon: Icons.history_rounded,
          label: 'Audit Logs'));
    }

    // Failsafe: if a user literally has zero permissions, give them an empty dashboard placeholder or POS
    if (dests.isEmpty) {
      dests.add(const _Dest(
          id: 'dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Dashboard'));
    }

    return dests;
  }

  Widget _screenForId(String id) {
    switch (id) {
      case 'dashboard':
        return const DashboardScreen();
      case 'analysis':
        return const AnalysisHubScreenAndroid();
      case 'pos':
        return const PosScreen();
      case 'warehouse':
        return const WarehouseScreen();
      case 'sales':
        return const SalesHistoryScreen();
      case 'staff':
        return const UserManagementScreen();
      case 'opd_queue':
        return const OpdQueueScreen();
      case 'patients':
        return const PatientListScreen();
      case 'doctors':
        return const DoctorListScreen();
      case 'opd_report':
        return const OpdReportScreen();
      case 'settings':
        return const SettingsScreen();
      case 'audit_logs':
        return const AuditLogsScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Start periodic Hub availability check for Cloud Mode
    _hubCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      final sync = context.read<SyncService>();
      if (sync.isCloudMode && sync.hubIp != null) {
        final reachable = await sync.testConnection(sync.hubIp!);
        if (reachable != _isHubBackOnline) {
          setState(() => _isHubBackOnline = reachable);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Load data
      context.read<InventoryProvider>().load();
      context.read<SalesProvider>().load();
      context.read<WarehouseProvider>().loadTransfers();
      context.read<OpdProvider>().loadAll();
      context.read<PrescriptionProvider>().load();

      // Start hub server on Windows
      if (Platform.isWindows) {
        await LocalServerService.instance.start();
        await DiscoveryService.startAdvertising(
            ObjectBoxService.instance.settings.serverPort);

        // Bug 4 Fix: Listen to incoming data pushes from Android and reload Windows providers
        LocalServerService.instance.incomingDataStream.listen((entityType) {
          if (!mounted) return;
          debugPrint(
              'AppShellAndroid [Windows]: incoming data push for $entityType — reloading providers');
          context.read<InventoryProvider>().load();
          context.read<SalesProvider>().load();
          context.read<OpdProvider>().loadAll();
          context.read<PatientProvider>().load();
          context.read<PrescriptionProvider>().load();
          context.read<TemplateProvider>().load();
          context.read<WarehouseProvider>().loadTransfers();
        });

        setState(() {});
      } else if (Platform.isAndroid) {
        await NotificationService.instance.init();

        // Check for updates
        unawaited(OtaUpdateService.checkForUpdate(context));

        // Bug 5 Fix: Auto-connect WebSocket after tryAutoConnect succeeds
        final sync = context.read<SyncService>();
        final connected = await sync.tryAutoConnect();
        if (connected && sync.hubIp != null && mounted) {
          debugPrint(
              'AppShellAndroid [Android]: Auto-connect succeeded, starting WebSocket to ${sync.hubIp}');
          context.read<WebSocketService>().connect(sync.hubIp!, sync.secret);
        }
      }

      // Listen to WebSocket events for real-time sync
      context.read<WebSocketService>().eventStream.listen((msg) async {
        if (!mounted) return;
        final sync = context.read<SyncService>();
        final event = msg['event'] as String? ?? '';
        if (event == 'new_patient' ||
            event == 'sync_received' ||
            event == 'medicines_updated' ||
            event == 'appointments_updated' ||
            event == 'patients_updated' ||
            event == 'sales_updated' ||
            event == 'sales_deleted' ||
            event == 'patient_deleted') {
          debugPrint('AppShellAndroid: Triggering pull cascade for $event...');

          try {
            final settings = ObjectBoxService.instance.settings;
            String? sinceStr;
            if (settings.lastGlobalSync != null) {
              sinceStr = DateTime.fromMillisecondsSinceEpoch(settings.lastGlobalSync!)
                  .subtract(const Duration(minutes: 1))
                  .toIso8601String();
            }

            if (event == 'medicines_updated') {
              await sync.pullMedicines(since: sinceStr);
              if (mounted) {
                context.read<InventoryProvider>().load();
              }
            } else if (event == 'appointments_updated') {
              await sync.pullAppointments();
              if (mounted) {
                context.read<OpdProvider>().loadAll();
              }
            } else if (event == 'patients_updated' || event == 'new_patient' || event == 'patient_deleted') {
              await sync.pullPatients(since: sinceStr);
              if (mounted) {
                context.read<PatientProvider>().load();
              }
            } else if (event == 'sales_updated' || event == 'sales_deleted') {
              await sync.pullSales(since: sinceStr);
              await sync.pullMedicines(since: sinceStr);
              if (mounted) {
                context.read<SalesProvider>().load();
                context.read<InventoryProvider>().load();
              }
            } else if (event == 'sync_received') {
              // Generic fallback (e.g. prescription updates)
              await sync.pullPrescriptions(since: sinceStr);
              await sync.pullAppointments();
              await sync.pullPatients(since: sinceStr);
              await sync.pullSales(since: sinceStr);
              if (mounted) {
                context.read<PrescriptionProvider>().load();
                context.read<OpdProvider>().loadAll();
                context.read<PatientProvider>().load();
                context.read<SalesProvider>().load();
              }
            }
          } catch (e) {
            debugPrint('AppShellAndroid: Sync failed: $e');
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    final wsvc = context.watch<WebSocketService>();
    final navProvider = context.watch<NavigationProvider>();
    final dests = _buildDestinations(context);

    int activeIndex = dests.indexWhere((d) => d.id == navProvider.activeDestId);
    if (activeIndex == -1) {
      activeIndex = 0;
    }

    final currentDestId = dests[activeIndex].id;
    final sync = context.watch<SyncService>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // 1. If not on Dashboard, go to Dashboard
        if (activeIndex != 0) {
          navProvider.selectDestination(dests[0].id);
          return;
        }

        // 2. If on Dashboard, implement double-back-to-exit
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Swipe back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        // 3. Exit the app
        SystemNavigator.pop();
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: null,
            body: isWide
                ? Row(
                    children: [
                      _SideNav(
                        selectedIndex: activeIndex,
                        onDestinationSelected: (i) =>
                            navProvider.selectDestination(dests[i].id),
                        destinations: dests,
                        isWindowsHub: Platform.isWindows,
                        isConnected: wsvc.connected,
                        onConnectTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ConnectionScreen())),
                      ),
                      Expanded(child: _screenForId(currentDestId)),
                    ],
                  )
                : Scaffold(
                    body: _screenForId(currentDestId),
                    bottomNavigationBar: navProvider.isBottomNavVisible
                        ? _ScrollableNavigationBar(
                            selectedIndex: activeIndex,
                            onDestinationSelected: (i) =>
                                navProvider.selectDestination(dests[i].id),
                            destinations: dests,
                          )
                        : null,
                    floatingActionButton: null,
                  ),
          ),
          
          // --- HUB OFFLINE OVERLAY (BLOCKING) ---
          if (!sync.isCloudMode && !wsvc.connected && sync.hubIp != null)
            ConnectivityOverlay(
              title: 'Hub Connection Lost',
              message: 'The Windows Hub is offline or unreachable. What would you like to do?',
              actions: [
                ElevatedButton.icon(
                  onPressed: () => showShopSelectionDialog(context),
                  icon: const Icon(Icons.cloud_sync),
                  label: const Text('Enter Cloud Mode (Firebase)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.warning,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    wsvc.connect(sync.hubIp!, sync.secret);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Connection'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ],
            ),

          // --- HUB BACK ONLINE OVERLAY (NON-BLOCKING PROMPT) ---
          if (sync.isCloudMode && _isHubBackOnline)
            ConnectivityOverlay(
              isBlocking: false,
              title: 'Hub is Back Online!',
              message: 'The Windows Hub is now reachable. Would you like to return to Live Mode for faster sync?',
              actions: [
                ElevatedButton.icon(
                  onPressed: () {
                    sync.exitCloudMode();
                    setState(() => _isHubBackOnline = false);
                    wsvc.connect(sync.hubIp!, sync.secret);
                  },
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Return to Live Mode'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _isHubBackOnline = false),
                  child: const Text('Dismiss (Stay in Cloud Mode)'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Dest {
  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _Dest(
      {required this.id,
      required this.icon,
      required this.selectedIcon,
      required this.label});
}

class _SideNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_Dest> destinations;
  final bool isWindowsHub;
  final bool isConnected;
  final VoidCallback onConnectTap;

  const _SideNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.isWindowsHub,
    required this.isConnected,
    required this.onConnectTap,
  });

  @override
  Widget build(BuildContext context) {
    final isExpanded = MediaQuery.of(context).size.width > 1100;

    return Container(
      width: isExpanded ? 220 : 72,
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(right: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.local_pharmacy,
                    color: AppTheme.primary, size: 28),
                if (isExpanded) ...[
                  const SizedBox(width: 10),
                  const Text('MediPoss',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppTheme.primary)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Nav items
          Expanded(
            child: ListView.builder(
              itemCount: destinations.length,
              itemBuilder: (ctx, i) {
                final d = destinations[i];
                final selected = selectedIndex == i;
                return InteractiveHover(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onDestinationSelected(i),
                  child: Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: InkWell(
                      onTap: () => onDestinationSelected(i),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Row(
                          children: [
                            Icon(selected ? d.selectedIcon : d.icon,
                                color: selected
                                    ? AppTheme.primary
                                    : context.textMutedColor,
                                size: 20),
                            if (isExpanded) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(d.label,
                                    style: TextStyle(
                                        color: selected
                                            ? AppTheme.primary
                                            : context.textMutedColor,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w400)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Logout Button
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
            ),
            child: InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.read<AuthProvider>().logout();
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: AppTheme.danger, size: 20),
                    if (isExpanded) ...[
                      const SizedBox(width: 12),
                      const Text('Logout',
                          style: TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Connection / Server status
          Padding(
            padding: const EdgeInsets.all(12),
            child: isWindowsHub
                ? _StatusBadge(
                    label: isExpanded ? 'Hub Active' : '',
                    color: AppTheme.success,
                    icon: Icons.router,
                  )
                : InkWell(
                    onTap: onConnectTap,
                    borderRadius: BorderRadius.circular(8),
                    child: _StatusBadge(
                      label: isExpanded
                          ? (isConnected ? 'Connected' : 'Connect Hub')
                          : '',
                      color: isConnected ? AppTheme.success : AppTheme.warning,
                      icon: isConnected ? Icons.link : Icons.link_off,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusBadge(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _ScrollableNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<_Dest> destinations;

  const _ScrollableNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: 0.8),
        border: Border(
            top: BorderSide(color: context.borderColor.withValues(alpha: 0.3))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: SizedBox(
              height: 72,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: List.generate(destinations.length, (i) {
                    final d = destinations[i];
                    final isSelected = selectedIndex == i;
                    return _NavItem(
                      dest: d,
                      isSelected: isSelected,
                      onTap: () => onDestinationSelected(i),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _Dest dest;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem(
      {required this.dest, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppTheme.primary : context.textMutedColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 90,
        padding: const EdgeInsets.symmetric(vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: Icon(
                isSelected ? dest.selectedIcon : dest.icon,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              dest.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: isSelected ? 0.2 : 0,
              ),
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
