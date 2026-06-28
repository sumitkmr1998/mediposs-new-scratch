import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';

class HubLauncherApp extends StatelessWidget {
  final Function(String shopId) onSelected;

  const HubLauncherApp({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediPoss Hub Launcher',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: HubLauncherScreen(onSelected: onSelected),
    );
  }
}

class HubLauncherScreen extends StatefulWidget {
  final Function(String shopId) onSelected;

  const HubLauncherScreen({super.key, required this.onSelected});

  @override
  State<HubLauncherScreen> createState() => _HubLauncherScreenState();
}

class _HubLauncherScreenState extends State<HubLauncherScreen> {
  List<String> _partitions = [];
  bool _loading = true;
  bool _alwaysAsk = false;
  final _newShopIdCtrl = TextEditingController();
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _scanPartitions();
  }

  Future<void> _scanPartitions() async {
    setState(() => _loading = true);
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final hubDbDir = Directory(p.join(appSupportDir.path, 'mediposs_db'));
      
      final prefs = await SharedPreferences.getInstance();
      _alwaysAsk = prefs.getBool('hub_always_ask_startup') ?? false;

      if (hubDbDir.existsSync()) {
        final List<String> foundPartitions = [];
        final entities = hubDbDir.listSync();
        for (final entity in entities) {
          if (entity is Directory) {
            final folderName = p.basename(entity.path);
            if (folderName != 'objectbox') {
              foundPartitions.add(folderName);
            }
          }
        }
        setState(() {
          _partitions = foundPartitions;
        });
      } else {
        setState(() {
          _partitions = ['default_shop'];
        });
      }
    } catch (e) {
      debugPrint('Error scanning hub partitions: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createPartition(String shopId) async {
    final cleanId = shopId.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    if (cleanId.isEmpty) {
      setState(() => _errorMsg = 'Invalid Shop ID. Use alphanumeric, dashes or underscores.');
      return;
    }
    if (_partitions.contains(cleanId)) {
      setState(() => _errorMsg = 'Shop ID already exists.');
      return;
    }

    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final newDir = Directory(p.join(appSupportDir.path, 'mediposs_db', cleanId));
      await newDir.create(recursive: true);
      
      _newShopIdCtrl.clear();
      _errorMsg = null;
      await _scanPartitions();
      
      // Auto select the newly created one
      _selectPartition(cleanId);
    } catch (e) {
      setState(() => _errorMsg = 'Failed to create shop partition folder: $e');
    }
  }

  Future<void> _selectPartition(String shopId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mediposs_active_shop_id', shopId);
    await prefs.setBool('hub_always_ask_startup', _alwaysAsk);
    widget.onSelected(shopId);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                        radius: 24,
                        child: const Icon(Icons.store, color: AppTheme.primary, size: 28),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MediPoss Hub Launcher',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Select Local Database Partition',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text(
                    'Select Hub Store/Shop to run:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _partitions.length,
                      itemBuilder: (ctx, i) {
                        final pName = _partitions[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 0,
                          color: context.surfaceColor.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: context.borderColor.withValues(alpha: 0.3)),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.dns, color: AppTheme.primaryLight),
                            title: Text(
                              pName == 'default_shop' ? 'Default Shop (Previous Data)' : pName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('ID: $pName', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            trailing: const Icon(Icons.play_circle_outline, color: AppTheme.success),
                            onTap: () => _selectPartition(pName),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Create new shop partition:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newShopIdCtrl,
                          decoration: const InputDecoration(
                            hintText: 'e.g., pharmacy_south_branch',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          onSubmitted: (val) => _createPartition(val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _createPartition(_newShopIdCtrl.text),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMsg!,
                      style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _alwaysAsk,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _alwaysAsk = val);
                          }
                        },
                      ),
                      const Text(
                        'Always prompt to select shop on startup',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
