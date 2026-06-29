import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../../shared/providers/inventory_provider.dart';
import '../../shared/providers/sales_provider.dart';
import '../../shared/providers/patient_provider.dart';
import '../../shared/providers/warehouse_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/prescription_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/providers/template_provider.dart';
import '../../shared/providers/navigation_provider.dart';
import '../../shared/services/local_server_service.dart';
import '../../shared/services/sync_service.dart';
import '../../shared/services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../shared/widgets/interactive_hover.dart';
import '../../widgets/exit_backup_dialog.dart';
import '../../shared/services/ota_update_service.dart';
import '../../widgets/shop_selection_dialog.dart';
import '../../shared/widgets/connectivity_overlay.dart';

import '../dashboard_screen.dart';
import '../pos_screen.dart';
import '../warehouse_screen.dart';
import '../sales_history_screen.dart';
import '../settings_screen.dart';
import '../connection_screen.dart';
import '../user_management_screen.dart';
import '../opd/opd_queue_screen.dart';
import '../opd/patient_list_screen.dart';
import '../opd/doctor_list_screen.dart';
import '../opd/opd_report_screen.dart';
import 'analysis_hub_screen.dart';
import '../audit_logs_screen.dart';

class AppShellWindows extends StatefulWidget {
  const AppShellWindows({super.key});

  @override
  State<AppShellWindows> createState() => _AppShellWindowsState();
}

class _AppShellWindowsState extends State<AppShellWindows> {
  int _selectedIndex = 0;
  bool _isForcedExit = false;
  bool _isCloudSyncing = false;
  Timer? _hubCheckTimer;
  bool _isHubBackOnline = false;

  @override
  void dispose() {
    _hubCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Start periodic Hub availability check for Cloud Mode
    _hubCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      final sync = context.read<SyncService>();
      final settings = context.read<SettingsProvider>().settings;
      if (settings.isWindowsClient && sync.isCloudMode && sync.hubIp != null) {
        final reachable = await sync.testConnection(sync.hubIp!);
        if (reachable != _isHubBackOnline) {
          setState(() => _isHubBackOnline = reachable);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1. Initial Data Load
      _loadInitialData();

      // 2. Settings & Initial Backup
      final settings = context.read<SettingsProvider>();
      await settings.load();
      settings.checkAndPerformAutoBackup('At Startup');

      // 3. Check for updates
      OtaUpdateService.checkForUpdate(context);

      // 4. Setup Periodic Tasks
      _setupPeriodicTasks();

      // 4. Setup Real-time Inbound Listeners
      _setupInboundListeners();

      // 5. Setup Professional Exit Workflow
      _setupExitWorkflow();
    });
  }

  void _loadInitialData() {
    context.read<InventoryProvider>().load();
    context.read<SalesProvider>().load();
    context.read<WarehouseProvider>().loadTransfers();
    context.read<OpdProvider>().loadAll();
    context.read<PrescriptionProvider>().load();
    context.read<PatientProvider>().load();
    context.read<TemplateProvider>().load();
  }

  void _setupPeriodicTasks() {
    Stream.periodic(const Duration(minutes: 30)).listen((_) {
      if (mounted) {
        context.read<SettingsProvider>().checkAndPerformAutoBackup('Periodic');
        context.read<WarehouseProvider>().loadTransfers();
      }
    });
  }

  void _setupInboundListeners() {
    if (Platform.isWindows) {
      LocalServerService.instance.incomingDataStream.listen((entityType) {
        if (!mounted) return;
        debugPrint('AppShellWindows: incoming data push for $entityType');
        if (entityType == 'settings') {
          context.read<SettingsProvider>().load();
        } else if (entityType == 'users') {
          context.read<AuthProvider>().notifyListeners();
        } else {
          _loadInitialData();
        }
      });
    }
  }

  void _setupExitWorkflow() {
    AppLifecycleListener(
      onExitRequested: () async {
        if (_isForcedExit) return AppExitResponse.exit;

        final settings = context.read<SettingsProvider>();
        final s = settings.settings;

        if (s.isWindowsClient) {
          return AppExitResponse.exit;
        }

        if (!s.firebaseEnabled && !s.googleDriveSyncEnabled) {
          return AppExitResponse.exit;
        }

        // We always want to perform Cloud Sync on exit, even if GDrive backup is off
        _showExitBackupDialog();
        return AppExitResponse.cancel;
      },
    );
  }

  void _showExitBackupDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExitBackupDialog(
        onForceExit: () {
          setState(() => _isForcedExit = true);
          SystemChannels.platform.invokeMethod('SystemNavigator.pop');
        },
      ),
    );

    final s = context.read<SettingsProvider>().settings;
    final futures = <Future>[];
    if (s.googleDriveSyncEnabled) {
      futures.add(context
          .read<SettingsProvider>()
          .checkAndPerformAutoBackup('On Close'));
    }
    if (s.firebaseEnabled) {
      futures.add(
        LocalServerService.instance.broadcastAllToCloud().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('Final Cloud Sync timed out on exit (AppShell).');
          },
        ),
      );
    }

    Future.wait(futures).then((_) {
      if (mounted && !_isForcedExit) {
        setState(() => _isForcedExit = true);
        SystemChannels.platform.invokeMethod('SystemNavigator.pop');
      }
    });
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
    if (auth.isAdmin || auth.currentUser?.role.toLowerCase() == 'manager') {
      dests.add(const _Dest(
          id: 'audit_logs',
          icon: Icons.history_toggle_off_rounded,
          selectedIcon: Icons.history_rounded,
          label: 'Audit Logs'));
    }
    if (auth.canAccessSettings) {
      dests.add(const _Dest(
          id: 'settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: 'Settings'));
    }

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
        return const AnalysisHubScreen();
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
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    final wsvc = context.watch<WebSocketService>();
    final nav = context.watch<NavigationProvider>();
    final sync = context.watch<SyncService>();
    final settings = context.watch<SettingsProvider>().settings;
    final dests = _buildDestinations(context);

    int activeIndex = dests.indexWhere((d) => d.id == nav.activeDestId);
    if (activeIndex == -1) activeIndex = 0;
    final currentDestId = dests[activeIndex].id;

    return Stack(
      children: [
        Scaffold(
          appBar: !isWide
              ? AppBar(
                  title: Text(dests[activeIndex].label),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout, color: AppTheme.danger),
                      onPressed: () => _showLogoutDialog(context),
                    ),
                  ],
                )
              : null,
          body: Row(
            children: [
              if (isWide)
                _SideNav(
                  selectedIndex: activeIndex,
                  onDestinationSelected: (i) =>
                      nav.selectDestination(dests[i].id),
                  destinations: dests,
                  isWindowsHub: !settings.isWindowsClient,
                  isConnected: wsvc.connected,
                  isCollapsed: settings.navCollapsed,
                  onToggleCollapse: () =>
                      context.read<SettingsProvider>().toggleNavCollapse(),
                  onConnectTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ConnectionScreen())),
                  onCloudSync: _performManualCloudSync,
                  isCloudSyncing: _isCloudSyncing,
                ),
              Expanded(child: _screenForId(currentDestId)),
            ],
          ),
        ),
        // --- HUB OFFLINE OVERLAY (BLOCKING) ---
        if (settings.isWindowsClient &&
            !sync.isCloudMode &&
            !wsvc.connected &&
            sync.hubIp != null)
          ConnectivityOverlay(
            title: 'Hub Connection Lost',
            message:
                'The Windows Hub is offline or unreachable. What would you like to do?',
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
        if (settings.isWindowsClient && sync.isCloudMode && _isHubBackOnline)
          ConnectivityOverlay(
            isBlocking: false,
            title: 'Hub is Back Online!',
            message:
                'The Windows Hub is now reachable. Would you like to return to Live Mode for faster sync?',
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
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _isHubBackOnline = false);
                },
                icon: const Icon(Icons.close),
                label: const Text('Dismiss'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _performManualCloudSync() async {
    setState(() => _isCloudSyncing = true);
    try {
      await LocalServerService.instance.broadcastAllToCloud();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Cloud Sync Complete! All data pushed to Firebase.'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Cloud Sync Failed: $e'),
          backgroundColor: AppTheme.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _isCloudSyncing = false);
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Logout from current session?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
  final bool isCollapsed;
  final VoidCallback onToggleCollapse;
  final VoidCallback onConnectTap;
  final VoidCallback onCloudSync;
  final bool isCloudSyncing;

  const _SideNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.isWindowsHub,
    required this.isConnected,
    required this.isCollapsed,
    required this.onToggleCollapse,
    required this.onConnectTap,
    required this.onCloudSync,
    required this.isCloudSyncing,
  });

  @override
  Widget build(BuildContext context) {
    final isWideWindow = MediaQuery.of(context).size.width > 1100;
    final expanded = isWideWindow && !isCollapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: expanded ? 220 : 72,
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(right: BorderSide(color: context.borderColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Icon(Icons.local_pharmacy,
                          color: Theme.of(context).colorScheme.primary,
                          size: 28),
                      if (expanded) ...[
                        const SizedBox(width: 10),
                        Flexible(
                            child: Text('MediPoss',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary))),
                      ],
                    ],
                  ),
                ),
                IconButton(
                    onPressed: onToggleCollapse,
                    icon: Icon(isCollapsed ? Icons.menu_open : Icons.menu,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.7),
                        size: 20)),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Icon(selected ? d.selectedIcon : d.icon,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : context.textMutedColor,
                            size: 20),
                        if (expanded) ...[
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(d.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: selected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : context.textMutedColor,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w400))),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _buildLogoutButton(context, expanded),
          const SizedBox(height: 8),
          if (isWindowsHub) ...[
            _buildCloudSyncButton(expanded),
            const SizedBox(height: 8),
          ],
          _buildStatusBadge(expanded),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCloudSyncButton(bool expanded) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: isCloudSyncing ? null : onCloudSync,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              if (isCloudSyncing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.sky,
                  ),
                )
              else
                const Icon(Icons.cloud_sync, color: AppTheme.sky, size: 20),
              if (expanded) ...[
                const SizedBox(width: 12),
                const Text(
                  'Cloud Sync',
                  style: TextStyle(
                    color: AppTheme.sky,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, bool expanded) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _showLogoutDialog(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.logout, color: AppTheme.danger, size: 20),
              if (expanded) ...[
                const SizedBox(width: 12),
                const Text('Logout',
                    style: TextStyle(
                        color: AppTheme.danger, fontWeight: FontWeight.w600))
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool expanded) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: isWindowsHub
          ? _StatusBadge(
              label: expanded ? 'Hub Active' : '',
              color: AppTheme.success,
              icon: Icons.router)
          : InkWell(
              onTap: onConnectTap,
              borderRadius: BorderRadius.circular(8),
              child: _StatusBadge(
                  label: expanded
                      ? (isConnected
                          ? 'Terminal: Connected'
                          : 'Terminal: Offline')
                      : '',
                  color: isConnected ? AppTheme.success : AppTheme.warning,
                  icon: isConnected ? Icons.link : Icons.link_off),
            ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)))
          ],
        ],
      ),
    );
  }
}
