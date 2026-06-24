import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../shared/models/audit_log.dart';
import '../shared/services/objectbox_service.dart';
import '../theme/app_theme.dart';
import '../shared/widgets/app_empty_state.dart';
import '../../objectbox.g.dart';

enum AuditDateFilter { today, yesterday, last7Days, allTime }

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _actionFilter = 'all'; // 'all', 'CREATE', 'UPDATE', 'DELETE', 'CANCEL', 'VOID', 'LOGIN'
  AuditDateFilter _dateFilter = AuditDateFilter.allTime;

  List<AuditLog> _logs = [];
  int _limit = 50;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    if (!ObjectBoxService.isInitialized) return;
    
    final box = ObjectBoxService.instance.auditLogBox;
    Condition<AuditLog>? cond;

    // Apply filters
    if (_actionFilter != 'all') {
      cond = AuditLog_.action.equals(_actionFilter);
    }

    final now = DateTime.now();
    DateTime? start;
    DateTime? end;

    if (_dateFilter == AuditDateFilter.today) {
      start = DateTime(now.year, now.month, now.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_dateFilter == AuditDateFilter.yesterday) {
      final y = now.subtract(const Duration(days: 1));
      start = DateTime(y.year, y.month, y.day);
      end = DateTime(y.year, y.month, y.day, 23, 59, 59);
    } else if (_dateFilter == AuditDateFilter.last7Days) {
      final startDay = now.subtract(const Duration(days: 6));
      start = DateTime(startDay.year, startDay.month, startDay.day);
      end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    }

    if (start != null && end != null) {
      final timeCond = AuditLog_.timestamp.between(
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      );
      cond = (cond == null) ? timeCond : cond.and(timeCond);
    }

    final queryBuilder = box.query(cond);

    // Sort descending by timestamp
    queryBuilder.order(AuditLog_.timestamp, flags: Order.descending);
    
    final query = queryBuilder.build();
    List<AuditLog> allMatched = query.find();
    query.close();

    // Client-side text search filter (performedBy, description, entityId)
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      allMatched = allMatched.where((log) {
        return log.performedBy.toLowerCase().contains(q) ||
            log.description.toLowerCase().contains(q) ||
            log.entityId.toLowerCase().contains(q) ||
            log.entityType.toLowerCase().contains(q);
      }).toList();
    }

    setState(() {
      _logs = allMatched;
    });
  }

  Color _actionColor(String action) {
    switch (action.toUpperCase()) {
      case 'CREATE':
        return AppTheme.success;
      case 'UPDATE':
        return AppTheme.primary;
      case 'DELETE':
      case 'VOID':
        return AppTheme.danger;
      case 'CANCEL':
        return AppTheme.danger;
      case 'LOGIN':
        return AppTheme.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _actionIcon(String action) {
    switch (action.toUpperCase()) {
      case 'CREATE':
        return LucideIcons.plusCircle;
      case 'UPDATE':
        return LucideIcons.edit;
      case 'DELETE':
      case 'VOID':
        return LucideIcons.trash2;
      case 'CANCEL':
        return LucideIcons.xCircle;
      case 'LOGIN':
        return LucideIcons.logIn;
      default:
        return LucideIcons.info;
    }
  }

  String _formatValue(String key, dynamic val) {
    if (val == null) return 'N/A';
    
    // If it's a String that looks like JSON, try to parse it
    if (val is String && (val.trim().startsWith('[') || val.trim().startsWith('{'))) {
      try {
        final parsed = jsonDecode(val);
        return _formatParsedValue(key, parsed);
      } catch (_) {
        // Fall back to original string
      }
    }
    
    return _formatParsedValue(key, val);
  }

  String _formatParsedValue(String key, dynamic val) {
    if (val == null) return 'N/A';
    
    if (val is List) {
      if (val.isEmpty) return 'Empty List';
      
      final items = <String>[];
      for (final item in val) {
        if (item is Map) {
          final qty = item['qty'] ?? item['quantity'] ?? '';
          final medName = item['medicineName'] ?? item['name'] ?? '';
          final total = item['lineTotal'] ?? item['total'] ?? '';
          final price = item['price'] ?? item['unitPrice'] ?? '';
          
          if (qty != '' && medName != '') {
            if (total != '') {
              items.add('• $qty x $medName (₹$total)');
            } else if (price != '') {
              items.add('• $qty x $medName (₹$price each)');
            } else {
              items.add('• $qty x $medName');
            }
            continue;
          }
          
          // Batch formatting
          final batchNo = item['batchNo'] ?? item['number'] ?? '';
          final mainStock = item['mainStock'] ?? '';
          final storeStock = item['storeStock'] ?? '';
          if (batchNo != '') {
            if (mainStock != '' && storeStock != '') {
              items.add('• Batch $batchNo (Main: $mainStock, Store: $storeStock)');
            } else if (mainStock != '') {
              items.add('• Batch $batchNo (Qty: $mainStock)');
            } else {
              items.add('• Batch $batchNo');
            }
            continue;
          }
          
          // General Map list item
          final parts = item.entries.map((e) => '${e.key}: ${e.value}').join(', ');
          items.add('• {$parts}');
        } else {
          items.add('• ${item.toString()}');
        }
      }
      return items.join('\n');
    }
    
    if (val is Map) {
      if (val.isEmpty) return 'Empty Map';
      final parts = <String>[];
      val.forEach((k, v) {
        parts.add('$k: ${_formatParsedValue(k, v)}');
      });
      return parts.join('\n');
    }
    
    return val.toString();
  }

  void _showDetailsDialog(AuditLog log) {
    Map<String, dynamic> details = {};
    try {
      details = jsonDecode(log.detailsJson);
    } catch (_) {}

    Map<String, String> changes = {};
    if (details.containsKey('before') && details.containsKey('after')) {
      final before = details['before'];
      final after = details['after'];
      if (before is Map<String, dynamic> && after is Map<String, dynamic>) {
        final allKeys = {...before.keys, ...after.keys};
        for (final key in allKeys) {
          final oldVal = before[key];
          final newVal = after[key];
          final oldStr = _formatValue(key, oldVal);
          final newStr = _formatValue(key, newVal);
          if (oldStr != newStr) {
            if (oldStr.contains('\n') || newStr.contains('\n')) {
              changes[key] = '$oldStr\n↓\n$newStr';
            } else {
              changes[key] = '$oldStr → $newStr';
            }
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _actionColor(log.action).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_actionIcon(log.action), color: _actionColor(log.action), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Audit Record Details',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width > 550 ? 500 : double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Timestamp', DateFormat('dd MMM yyyy, hh:mm:ss a').format(log.timestamp)),
                _buildDetailRow('Action', log.action, isBadge: true, badgeColor: _actionColor(log.action)),
                _buildDetailRow('Actor', log.performedBy),
                _buildDetailRow('Entity Type', log.entityType),
                _buildDetailRow('Entity ID', log.entityId),
                _buildDetailRow('Device ID', log.deviceId),
                _buildDetailRow('Description', log.description),
                if (changes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'CHANGED FIELDS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.amber),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: changes.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 130,
                              child: Text(
                                e.key,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.value,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: const Text(
                        'RAW METADATA',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey),
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      expandedAlignment: Alignment.topLeft,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Text(
                            const JsonEncoder.withIndent('  ').convert(details),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.lightGreen),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBadge = false, Color? badgeColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: isBadge
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? Colors.grey).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        value,
                        style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                : Text(
                    value,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayedLogs = _logs.take(_limit).toList();
    final hasMore = _logs.length > _limit;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.shieldAlert, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'System Audit Logs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Verifiable trail of actions, operations, and events',
                  style: TextStyle(fontSize: 11, color: context.textMutedColor),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Filter Panel
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    final searchField = TextField(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        setState(() => _searchQuery = v);
                        _loadLogs();
                      },
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search logs (Actor, Invoice No, Medicine)...',
                        prefixIcon: const Icon(LucideIcons.search, size: 16),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );

                    final dropdown = Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.borderColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _actionFilter,
                          isExpanded: true,
                          icon: const Icon(LucideIcons.chevronDown, size: 14),
                          style: TextStyle(color: context.textColor, fontSize: 13, fontWeight: FontWeight.bold),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _actionFilter = val);
                              _loadLogs();
                            }
                          },
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All Actions')),
                            DropdownMenuItem(value: 'CREATE', child: Text('CREATE')),
                            DropdownMenuItem(value: 'UPDATE', child: Text('UPDATE')),
                            DropdownMenuItem(value: 'CANCEL', child: Text('CANCEL')),
                            DropdownMenuItem(value: 'VOID', child: Text('VOID / REFUND')),
                            DropdownMenuItem(value: 'LOGIN', child: Text('LOGIN')),
                          ],
                        ),
                      ),
                    );

                    if (isMobile) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          searchField,
                          const SizedBox(height: 12),
                          dropdown,
                        ],
                      );
                    } else {
                      return Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 16),
                          SizedBox(width: 180, child: dropdown),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'DATE RANGE: ',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: context.textMutedColor),
                      ),
                      const SizedBox(width: 12),
                      _buildDateChip('All Time', AuditDateFilter.allTime),
                      const SizedBox(width: 8),
                      _buildDateChip('Today', AuditDateFilter.today),
                      const SizedBox(width: 8),
                      _buildDateChip('Yesterday', AuditDateFilter.yesterday),
                      const SizedBox(width: 8),
                      _buildDateChip('Last 7 Days', AuditDateFilter.last7Days),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main list
          Expanded(
            child: _logs.isEmpty
                ? const AppEmptyState(
                    icon: LucideIcons.shield,
                    title: 'No audit logs found',
                    subtitle: 'Try adjusting your search queries or filter categories.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: displayedLogs.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      if (i == displayedLogs.length) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: OutlinedButton(
                              onPressed: () => setState(() => _limit += 50),
                              child: const Text('Load More Log Entries'),
                            ),
                          ),
                        );
                      }

                      final log = displayedLogs[i];
                      final actColor = _actionColor(log.action);
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: context.borderColor.withValues(alpha: 0.3)),
                        ),
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showDetailsDialog(log),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              children: [
                                // Action Icon
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: actColor.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(_actionIcon(log.action), color: actColor, size: 18),
                                ),
                                const SizedBox(width: 16),
                                // Text Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.description,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.user, size: 12, color: context.textMutedColor),
                                              const SizedBox(width: 4),
                                              Text(
                                                log.performedBy,
                                                style: TextStyle(fontSize: 11, color: context.textMutedColor, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(LucideIcons.cpu, size: 12, color: context.textMutedColor),
                                              const SizedBox(width: 4),
                                              Text(
                                                log.entityType,
                                                style: TextStyle(fontSize: 11, color: context.textMutedColor),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Timestamp
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      DateFormat('hh:mm a').format(log.timestamp),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      DateFormat('dd MMM yyyy').format(log.timestamp),
                                      style: TextStyle(fontSize: 10, color: context.textMutedColor),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ).animate().fade(duration: 200.ms);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, AuditDateFilter value) {
    final selected = _dateFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (sel) {
        if (sel) {
          setState(() => _dateFilter = value);
          _loadLogs();
        }
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? AppTheme.primary : context.textMutedColor,
      ),
    );
  }
}
