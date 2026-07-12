import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../shared/services/cloudflare_service.dart';
import '../../../../shared/services/local_server_service.dart';
import '../../../../shared/services/ota_update_service.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/settings_widgets.dart';

class InterfaceSection extends StatelessWidget {
  final String selectedTheme;
  final bool enableAnimations;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<bool> onAnimationsChanged;

  const InterfaceSection({
    super.key,
    required this.selectedTheme,
    required this.enableAnimations,
    required this.onThemeChanged,
    required this.onAnimationsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'USER INTERFACE PREFERENCES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppTheme.purple,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Customize application appearance themes, color settings, and animation preferences.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'UI Preferences',
          icon: LucideIcons.monitor,
          children: [
            SettingsDropdown<String>(
              title: 'Visual Theme',
              value: selectedTheme,
              icon: LucideIcons.palette,
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System Preference')),
                DropdownMenuItem(value: 'light', child: Text('Light Mode')),
                DropdownMenuItem(value: 'dark', child: Text('Dark Mode')),
              ],
              onChanged: (val) {
                if (val != null) onThemeChanged(val);
              },
            ),
            const Divider(),
            SettingsSwitch(
              title: 'Premium Animations',
              subtitle: 'Enable smooth entrance and layout transitions',
              value: enableAnimations,
              icon: LucideIcons.sparkles,
              onChanged: onAnimationsChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class NetworkingSection extends StatefulWidget {
  final bool isWindowsClient;
  final TextEditingController portCtrl;
  final String? hubIp;
  final SyncService syncService;
  final ValueChanged<bool> onWindowsClientChanged;

  const NetworkingSection({
    super.key,
    required this.isWindowsClient,
    required this.portCtrl,
    required this.hubIp,
    required this.syncService,
    required this.onWindowsClientChanged,
  });

  @override
  State<NetworkingSection> createState() => _NetworkingSectionState();
}

class _NetworkingSectionState extends State<NetworkingSection> {
  Widget _buildInfoCard(String title, String value, IconData icon, String hint, {bool isLink = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryLight),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 14),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
                tooltip: 'Copy',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isLink ? AppTheme.primary : context.textColor,
              decoration: isLink ? TextDecoration.underline : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(hint, style: TextStyle(fontSize: 11, color: context.textMutedColor)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverRunning = LocalServerService.instance.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NETWORKING & MULTI-DEVICE SYNC',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure this PC to run as the main Hub or a Terminal Client, and view sync connection links.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final useHorizontal = constraints.maxWidth > 1000;
            
            final roleCard = SettingsSection(
              title: 'Connection Role',
              icon: LucideIcons.cpu,
              children: [
                SettingsSwitch(
                  title: 'Act as Terminal (Client Mode)',
                  subtitle: 'Enable this if this PC should connect to a Main Hub PC instead of being the Hub itself.',
                  value: widget.isWindowsClient,
                  icon: LucideIcons.monitorSpeaker,
                  onChanged: (val) {
                    widget.onWindowsClientChanged(val);
                    if (val) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('App will restart in Client Mode after saving.'),
                        backgroundColor: AppTheme.warning,
                      ));
                    }
                  },
                ),
              ],
            );

            final serverCard = SettingsSection(
              title: widget.isWindowsClient ? 'Terminal Status' : 'Local Hub Server',
              icon: widget.isWindowsClient ? LucideIcons.link : LucideIcons.server,
              children: !widget.isWindowsClient ? [
                Row(
                  children: [
                    Icon(
                      LucideIcons.activity,
                      color: serverRunning ? AppTheme.success : AppTheme.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      serverRunning ? 'Sync Server: ACTIVE' : 'Sync Server: STOPPED',
                      style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsField(controller: widget.portCtrl, label: 'Hub Sync Port', icon: LucideIcons.hash, keyboardType: TextInputType.number),
                const Text(
                  'Android clients must specify this port to connect to this Hub.',
                  style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
                const Divider(height: 32),
                _buildInfoCard(
                  'Local Network Address',
                  widget.hubIp ?? 'Finding IP...',
                  LucideIcons.wifi,
                  'Use this IP in the companion app while on the same Wi-Fi.',
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  'Cloudflare Tunnel Link',
                  CloudflareService.instance.currentUrl ?? 'No active tunnel',
                  LucideIcons.globe,
                  'Use this URL to connect remotely from anywhere in the world.',
                  isLink: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => const AlertDialog(
                          content: Row(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(width: 20),
                              Text('Redeploying Cloudflare Tunnel...'),
                            ],
                          ),
                        ),
                      );
                      try {
                        await CloudflareService.instance.redeploy();
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cloudflare Tunnel redeployed successfully!')),
                          );
                          setState(() {});
                        }
                      } catch (e) {
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Redeployment failed: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: const Text('Redeploy Cloudflare Tunnel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),
              ] : [
                const Text(
                  'This PC is currently acting as a Terminal Client. It will connect to the master Hub for all data.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  'Connected Hub IP',
                  widget.syncService.hubIp ?? 'Not Connected',
                  LucideIcons.server,
                  'The IP address of the main Windows Hub.',
                ),
              ],
            );

            if (useHorizontal) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: roleCard),
                  const SizedBox(width: 24),
                  Expanded(child: serverCard),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  roleCard,
                  serverCard,
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

class InventorySection extends StatelessWidget {
  final TextEditingController lowStockCtrl;
  final TextEditingController nearExpiryCtrl;

  const InventorySection({
    super.key,
    required this.lowStockCtrl,
    required this.nearExpiryCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'INVENTORY ALERTS & THRESHOLDS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adjust critical stock alerts and expiry warning ranges for catalog medicines.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Threshold Monitoring',
          icon: LucideIcons.alertCircle,
          children: [
            SettingsField(controller: lowStockCtrl, label: 'Low Stock Level', icon: LucideIcons.alertTriangle, keyboardType: TextInputType.number),
            SettingsField(controller: nearExpiryCtrl, label: 'Expiry Warning (Days)', icon: LucideIcons.timer, keyboardType: TextInputType.number),
          ],
        ),
      ],
    );
  }
}

class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SOFTWARE UPDATE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: Colors.pink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Check for new version of MediPoss and update the portable client automatically.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        SettingsSection(
          title: 'Software Update Management',
          icon: LucideIcons.download,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.system_update_rounded,
                    color: AppTheme.primary, size: 20),
              ),
              title: const Text('Check for Updates',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Check for new version on Firebase Storage',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                OtaUpdateService.checkForUpdate(context, forceShowNoUpdate: true);
              },
            ),
          ],
        ),
      ],
    );
  }
}
