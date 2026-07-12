import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../../../theme/app_theme.dart';
import '../../widgets/settings_widgets.dart';

class CloudSection extends StatelessWidget {
  final SettingsProvider settingsProv;
  final bool googleDriveSyncEnabled;
  final bool firebaseEnabled;
  final bool firebaseMirrorEnabled;
  final bool firebaseSummaryEnabled;
  final TextEditingController shopIdCtrl;
  final String autoBackupFreq;
  final String autoBackupLogic;
  
  final ValueChanged<bool> onGoogleDriveSyncEnabledChanged;
  final ValueChanged<bool> onFirebaseEnabledChanged;
  final ValueChanged<bool> onFirebaseMirrorEnabledChanged;
  final ValueChanged<bool> onFirebaseSummaryEnabledChanged;
  final ValueChanged<String> onAutoBackupFreqChanged;
  final ValueChanged<String> onAutoBackupLogicChanged;
  final VoidCallback onSyncTodayNow;
  final VoidCallback onShowRestoreDialog;
  final VoidCallback onSelectBackupTime;

  const CloudSection({
    super.key,
    required this.settingsProv,
    required this.googleDriveSyncEnabled,
    required this.firebaseEnabled,
    required this.firebaseMirrorEnabled,
    required this.firebaseSummaryEnabled,
    required this.shopIdCtrl,
    required this.autoBackupFreq,
    required this.autoBackupLogic,
    required this.onGoogleDriveSyncEnabledChanged,
    required this.onFirebaseEnabledChanged,
    required this.onFirebaseMirrorEnabledChanged,
    required this.onFirebaseSummaryEnabledChanged,
    required this.onAutoBackupFreqChanged,
    required this.onAutoBackupLogicChanged,
    required this.onSyncTodayNow,
    required this.onShowRestoreDialog,
    required this.onSelectBackupTime,
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
                'CLOUD SERVICES & BACKUP STRATEGY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppTheme.sky,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure Google Drive linking, set up multi-tenant companion app sync, or adjust automatic background backups.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final useHorizontal = constraints.maxWidth > 1000;
            
            final leftCol = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsSection(
                  title: 'Google Drive Cloud Sync',
                  icon: LucideIcons.cloud,
                  children: [
                    SettingsSwitch(
                      title: 'Enable Google Drive Sync',
                      subtitle: 'Allow backups to Google Drive (on close/periodic/manual)',
                      value: googleDriveSyncEnabled,
                      icon: LucideIcons.cloud,
                      onChanged: onGoogleDriveSyncEnabledChanged,
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: settingsProv.settings.googleDriveLinked ? AppTheme.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          child: Icon(
                            settingsProv.settings.googleDriveLinked ? LucideIcons.cloudLightning : LucideIcons.cloudOff,
                            color: settingsProv.settings.googleDriveLinked ? AppTheme.success : AppTheme.danger,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                settingsProv.settings.googleDriveLinked ? 'Google Connected' : 'Google Drive Disconnected',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                settingsProv.settings.googleDriveLinked 
                                  ? 'Automated backups are configured and running.' 
                                  : 'Connect Google account to enable cloud backups.',
                                style: TextStyle(color: context.textMutedColor, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (!settingsProv.settings.googleDriveLinked)
                          ElevatedButton.icon(
                            onPressed: settingsProv.isGoogleLoading ? null : () => settingsProv.linkGoogleDrive(),
                            icon: const Icon(LucideIcons.chrome, size: 16),
                            label: Text(settingsProv.isGoogleLoading ? 'Connecting...' : 'Link'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.sky),
                          )
                        else
                          TextButton.icon(
                            onPressed: () => settingsProv.unlinkGoogleDrive(),
                            icon: const Icon(LucideIcons.logOut, size: 16),
                            label: const Text('Disconnect'),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                          ),
                      ],
                    ),
                    if (settingsProv.settings.googleDriveLinked) ...[
                      const Divider(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Last Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(
                                  settingsProv.settings.lastBackupMillis != null 
                                    ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(settingsProv.settings.lastBackupMillis!))
                                    : 'No backups recorded',
                                  style: TextStyle(color: context.textMutedColor, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: settingsProv.isGoogleLoading ? null : () async {
                              final success = await settingsProv.performManualBackup();
                              if (success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup Success!'), backgroundColor: AppTheme.success));
                              } else if (!success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('Backup Failed: ${settingsProv.googleError ?? 'Unknown Error'}'), 
                                  backgroundColor: AppTheme.danger,
                                ));
                              }
                            },
                            icon: settingsProv.isGoogleLoading 
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(LucideIcons.uploadCloud, size: 16),
                            label: const Text('Sync Now'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: settingsProv.isGoogleLoading ? null : onShowRestoreDialog,
                            icon: const Icon(LucideIcons.downloadCloud, size: 16),
                            label: const Text('Restore'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.warning,
                              side: const BorderSide(color: AppTheme.warning),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                SettingsSection(
                  title: 'Multi-Tenant Firebase Sync',
                  icon: LucideIcons.database,
                  children: [
                    SettingsSwitch(
                      title: 'Enable Firebase Integration',
                      subtitle: 'Enables status discovery and sync features',
                      value: firebaseEnabled,
                      icon: LucideIcons.database,
                      onChanged: onFirebaseEnabledChanged,
                    ),
                    if (firebaseEnabled) ...[
                      const SizedBox(height: 16),
                      SettingsSwitch(
                        title: 'Enable Cloud Database Mirroring',
                        subtitle: 'Uploads new/updated sales, medicines, and patients incrementally from now onwards (conserves quota)',
                        value: firebaseMirrorEnabled,
                        icon: LucideIcons.cloud,
                        onChanged: onFirebaseMirrorEnabledChanged,
                      ),
                      const SizedBox(height: 16),
                      SettingsSwitch(
                        title: 'Enable Daily Cloud Summary Upload',
                        subtitle: "Uploads today's sales, prescriptions, and patients daily at scheduled time",
                        value: firebaseSummaryEnabled,
                        icon: LucideIcons.calendar,
                        onChanged: onFirebaseSummaryEnabledChanged,
                      ),
                    ],
                    const SizedBox(height: 16),
                    SettingsField(
                      controller: shopIdCtrl, 
                      label: 'Shop ID (Leave blank to auto-generate)', 
                      icon: LucideIcons.store,
                      enabled: firebaseEnabled,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        'Changing this ID partitions your cloud database. Companion apps must use this exact ID to sync.',
                        style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (firebaseEnabled) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: OutlinedButton.icon(
                            onPressed: onSyncTodayNow,
                            icon: const Icon(LucideIcons.cloud, size: 16),
                            label: const Text("Sync Today's Data Now"),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            );

            final rightCol = SettingsSection(
              title: 'Automated Backups',
              icon: LucideIcons.calendarClock,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
                  child: Text(
                    'Automated backups are stored locally. If Google Drive is connected, they will also sync to the cloud.',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
                SettingsDropdown<String>(
                  title: 'Frequency Strategy',
                  value: autoBackupFreq,
                  icon: LucideIcons.calendar,
                  items: const ['Never', 'Daily', 'Weekly', 'Monthly']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) onAutoBackupFreqChanged(val);
                  },
                ),
                if (autoBackupFreq != 'Never')
                  ListTile(
                    leading: const Icon(LucideIcons.clock, size: 20),
                    title: const Text('Scheduled Time', style: TextStyle(fontSize: 14)),
                    subtitle: Text(settingsProv.settings.autoBackupTime ?? 'Select Time', style: const TextStyle(color: AppTheme.primary)),
                    trailing: const Icon(LucideIcons.chevronRight, size: 16),
                    onTap: onSelectBackupTime,
                  ),
                const Divider(),
                SettingsDropdown<String>(
                  title: 'Trigger Logic',
                  value: autoBackupLogic,
                  icon: LucideIcons.cog,
                  items: const ['At Startup', 'On Close', 'Periodic']
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) onAutoBackupLogicChanged(val);
                  },
                ),
              ],
            );

            if (useHorizontal) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftCol),
                  const SizedBox(width: 24),
                  Expanded(child: rightCol),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leftCol,
                  rightCol,
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

class DataSection extends StatelessWidget {
  final int auditRetentionDays;
  final ValueChanged<int> onAuditRetentionDaysChanged;
  
  final VoidCallback onExportExcel;
  final VoidCallback onImportExcel;
  final VoidCallback onBackupDatabase;
  final VoidCallback onRestoreDatabase;
  final VoidCallback onBackupJsonGranular;
  final VoidCallback onRestoreJsonGranular;
  final VoidCallback onGenerateAuditReport;
  final VoidCallback onSeedCustomDemoData;

  const DataSection({
    super.key,
    required this.auditRetentionDays,
    required this.onAuditRetentionDaysChanged,
    required this.onExportExcel,
    required this.onImportExcel,
    required this.onBackupDatabase,
    required this.onRestoreDatabase,
    required this.onBackupJsonGranular,
    required this.onRestoreJsonGranular,
    required this.onGenerateAuditReport,
    required this.onSeedCustomDemoData,
  });

  Widget _buildFeatureCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required List<Widget> actions,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkCard
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outline.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'DATABASE ACTION',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: accentColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(color: context.textMutedColor, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: actions),
        ],
      ),
    );
  }

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
                'DATA MANAGEMENT CONTROL CENTER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppTheme.primaryLight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure catalog exchange sheets, raw snapshots, modular recovery zips, or export legal ledger audits.',
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 900 ? 2 : 1;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: cols == 2 ? 1.6 : 2.0,
              children: [
                // 1. Excel Card
                _buildFeatureCard(
                  context: context,
                  title: 'Excel Data Exchange',
                  subtitle: 'Bulk export collection catalog or import stock lists directly to/from MS Excel sheets.',
                  icon: LucideIcons.fileSpreadsheet,
                  accentColor: AppTheme.emerald,
                  actions: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onExportExcel,
                        icon: const Icon(LucideIcons.fileOutput, size: 16),
                        label: const Text('Export Collection', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onImportExcel,
                        icon: const Icon(LucideIcons.plusCircle, size: 16),
                        label: const Text('Import Catalog', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.emerald,
                          side: const BorderSide(color: AppTheme.emerald),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                // 2. MDB Database Card
                _buildFeatureCard(
                  context: context,
                  title: 'Direct Database Snap (.mdb)',
                  subtitle: 'Low-level direct backup copy of the ObjectBox database files. Overwriting completely resets local tables.',
                  icon: LucideIcons.database,
                  accentColor: AppTheme.indigo,
                  actions: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onBackupDatabase,
                        icon: const Icon(LucideIcons.save, size: 16),
                        label: const Text('Download .mdb', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.indigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRestoreDatabase,
                        icon: const Icon(LucideIcons.history, size: 16),
                        label: const Text('Restore .mdb', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                // 3. Zip Archives Card
                _buildFeatureCard(
                  context: context,
                  title: 'Full System JSON Backups',
                  subtitle: 'Local .zip package backups including modular database JSON tables, patient photos, and doctor prescriptions.',
                  icon: LucideIcons.archive,
                  accentColor: AppTheme.primary,
                  actions: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onBackupJsonGranular,
                        icon: const Icon(LucideIcons.archive, size: 16),
                        label: const Text('Export Backup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRestoreJsonGranular,
                        icon: const Icon(LucideIcons.history, size: 16),
                        label: const Text('Restore Backup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: 'Open Automated Backups Folder',
                      icon: const Icon(LucideIcons.folder, size: 18),
                      onPressed: () async {
                        final appSupportDir = await getApplicationSupportDirectory();
                        final backupDir = Directory(p.join(appSupportDir.path, 'backups'));
                        if (await backupDir.exists()) {
                          launchUrl(Uri.file(backupDir.path));
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No automated backups created yet.')));
                        }
                      },
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        padding: const EdgeInsets.all(14),
                      ),
                    ),
                  ],
                ),
                // 4. Audits Card
                _buildFeatureCard(
                  context: context,
                  title: 'Comprehensive Audits',
                  subtitle: 'Exports readable spreadsheets detailing stocks, internal transfers (with names), sales history, patients, and clinical prescriptions.',
                  icon: LucideIcons.clipboardCheck,
                  accentColor: AppTheme.sky,
                  actions: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onGenerateAuditReport,
                        icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
                        label: const Text('Generate Audit Report (.xlsx)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.sky,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                // 5. Demo Data Seeding Card
                _buildFeatureCard(
                  context: context,
                  title: 'Demo Data Seeding',
                  subtitle: 'Populate database with 6 months of realistic data: 30 patients, 30 dispenses, 20 retail sales daily (avg cart value 1500, avg 5 items), and 10 stock transfers daily.',
                  icon: LucideIcons.database,
                  accentColor: Colors.purple,
                  actions: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onSeedCustomDemoData,
                        icon: const Icon(LucideIcons.playCircle, size: 16),
                        label: const Text('Seed 6-Month Data', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        SettingsSection(
          title: 'System Audit Logs Policy',
          icon: LucideIcons.shieldAlert,
          children: [
            SettingsDropdown<int>(
              title: 'Keep Audit Logs For',
              value: auditRetentionDays,
              icon: LucideIcons.history,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Keep Forever')),
                DropdownMenuItem(value: 30, child: Text('30 Days')),
                DropdownMenuItem(value: 90, child: Text('90 Days')),
                DropdownMenuItem(value: 180, child: Text('180 Days')),
                DropdownMenuItem(value: 365, child: Text('1 Year')),
                DropdownMenuItem(value: 730, child: Text('2 Years')),
                DropdownMenuItem(value: 1095, child: Text('3 Years')),
              ],
              onChanged: (val) {
                if (val != null) onAuditRetentionDaysChanged(val);
              },
            ),
          ],
        ),
      ],
    );
  }
}
