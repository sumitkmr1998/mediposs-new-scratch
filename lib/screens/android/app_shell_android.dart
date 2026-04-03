import 'dart:io';
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
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/opd_provider.dart';
import '../../shared/providers/prescription_provider.dart';
import '../../shared/providers/template_provider.dart';
import '../../shared/widgets/interactive_hover.dart';

class AppShellAndroid extends StatefulWidget {
  const AppShellAndroid({super.key});

  @override
  State<AppShellAndroid> createState() => _AppShellAndroidState();
}

class _AppShellAndroidState extends State<AppShellAndroid> {
  int _selectedIndex = 0;

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

    if (auth.canManageUsers) {
      dests.add(const _Dest(
          id: 'staff',
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: 'Staff'));
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
      dests.add(const _Dest(
          id: 'doctors',
          icon: Icons.medical_services_outlined,
          selectedIcon: Icons.medical_services,
          label: 'Doctors'));
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
      default:
        return const DashboardScreen();
    }
  }

  @override
  void initState() {
    super.initState();
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

        // Bug 5 Fix: Auto-connect WebSocket after tryAutoConnect succeeds
        final sync = context.read<SyncService>();
        final connected = await sync.tryAutoConnect();
        if (connected && sync.hubIp != null) {
          debugPrint(
              'AppShellAndroid [Android]: Auto-connect succeeded, starting WebSocket to ${sync.hubIp}');
          context.read<WebSocketService>().connect(sync.hubIp!);
        }
      }

      // Listen to WebSocket events for real-time sync
      context.read<WebSocketService>().eventStream.listen((msg) async {
        if (!mounted) return;
        final sync = context.read<SyncService>();
        if (msg['event'] == 'new_patient' ||
            msg['event'] == 'sync_received' ||
            msg['event'] == 'medicines_updated') {
          // Pull everything on any sync event to ensure consistency
          await sync.pullMedicines();
          await sync.pullPatients();
          await sync.pullAppointments();
          await sync.pullDoctors();
          await sync.pullPrescriptions();
          await sync.pullSales();
          await sync.pullTransfers();
          await sync.pullTemplates();
          // Note: patient photos are loaded lazily when Gallery tab opens

          if (mounted) {
            context.read<PatientProvider>().load();
            context.read<OpdProvider>().loadAll();
            context.read<SalesProvider>().load();
            context.read<InventoryProvider>().load();
            context.read<PrescriptionProvider>().load();
            context.read<TemplateProvider>().load();
            context.read<WarehouseProvider>().loadTransfers();
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    final wsvc = context.watch<WebSocketService>();
    final dests = _buildDestinations(context);

    // Safety check just in case permissions shrunk and index is out of bounds
    if (_selectedIndex >= dests.length) {
      _selectedIndex = 0;
    }

    final currentDestId = dests[_selectedIndex].id;

    return Scaffold(
      appBar: null,
      body: isWide
          ? Row(
              children: [
                _SideNav(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _selectedIndex = i),
                  destinations: dests,
                  isWindowsHub: Platform.isWindows,
                  isConnected: wsvc.connected,
                  onConnectTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ConnectionScreen())),
                ),
                Expanded(child: _screenForId(currentDestId)),
              ],
            )
          : Scaffold(
              body: _screenForId(currentDestId),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (i) =>
                    setState(() => _selectedIndex = i),
                destinations: dests
                    .map((d) => NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: d.label,
                        ))
                    .toList(),
              ),
              floatingActionButton: null,
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
