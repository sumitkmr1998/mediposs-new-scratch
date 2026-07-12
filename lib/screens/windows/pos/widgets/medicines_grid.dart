import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../shared/providers/inventory_provider.dart';
import '../../../../shared/providers/cart_provider.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/procedure_provider.dart';
import '../../../../shared/models/medicine.dart';
import '../../../../shared/models/patient.dart';
import '../../../../shared/models/procedure.dart';
import '../../../../shared/services/sync_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/patient_dialogs.dart';
import '../../../../widgets/procedure_dialog.dart';
import 'product_card.dart';

class MedicinesGrid extends StatefulWidget {
  final InventoryProvider inv;
  final CartProvider cart;
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final VoidCallback onSearchEnter;
  final ValueChanged<FocusNode> onFirstGridFocusNodeCreated;
  final Function(Medicine) onAddToGrid;
  final Function(String) onItemAddedToCart;
  final VoidCallback onScanTap;

  const MedicinesGrid({
    super.key,
    required this.inv,
    required this.cart,
    required this.searchCtrl,
    required this.searchFocus,
    required this.onSearchEnter,
    required this.onFirstGridFocusNodeCreated,
    required this.onAddToGrid,
    required this.onItemAddedToCart,
    required this.onScanTap,
  });

  @override
  State<MedicinesGrid> createState() => MedicinesGridState();
}

class MedicinesGridState extends State<MedicinesGrid> {
  // Map of Grid Item ID -> FocusNode (for keyboard navigation in the grid)
  final Map<String, FocusNode> _gridFocusNodes = {};

  @override
  void dispose() {
    for (var node in _gridFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _getGridFocusNode(String key, bool isFirst) {
    if (!_gridFocusNodes.containsKey(key)) {
      final node = FocusNode();
      _gridFocusNodes[key] = node;
      if (isFirst) {
        widget.onFirstGridFocusNodeCreated(node);
      }
    }
    return _gridFocusNodes[key]!;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final procProv = context.watch<ProcedureProvider>();
    final query = widget.searchCtrl.text.toLowerCase();

    final isClinical = widget.cart.isClinicalDispense;
    final medicines = widget.inv.rawMedicines
        .where((m) => isClinical ? m.getNonExpiredMainStock() > 0 : m.getNonExpiredStoreStock() > 0)
        .where(
          (m) =>
              query.isEmpty ||
              m.name.toLowerCase().contains(query) ||
              m.barcode.contains(query),
        )
        .toList();

    final procedures = procProv.procedures
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();

    final List<dynamic> combined = [...medicines, ...procedures];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        // Pipeline Step 1: User presses Down Arrow in search -> Focus First Grid Item
                        if (combined.isNotEmpty) {
                          final first = combined.first;
                          final key = first is Medicine
                              ? 'm_${first.id}'
                              : 'p_${first.id}';
                          _getGridFocusNode(
                            key,
                            true,
                          ).requestFocus();
                        }
                      }
                    }
                  },
                  child: TextField(
                    controller: widget.searchCtrl,
                    focusNode: widget.searchFocus,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => widget.onSearchEnter(),
                    decoration: const InputDecoration(
                      hintText:
                          'Search medicine [Down for list, Enter to Checkout]...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!kIsWeb && !Platform.isWindows) ...[
                IconButton(
                  icon: Icon(
                    Icons.qr_code_scanner,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  tooltip: 'Scan Barcode',
                  onPressed: widget.onScanTap,
                ),
                const SizedBox(width: 4),
              ],
              if (auth.hasInventoryWriteAccess) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.person_add_alt_1,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  tooltip: 'Add Patient to OPD',
                  onPressed: () => _showPatientQueueDialog(context),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.auto_awesome_motion,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  tooltip: 'Quick Add Procedure',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const ProcedureDialog(),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Calculate crossAxisCount based on SliverGridDelegateWithMaxCrossAxisExtent logic
              final int crossAxisCount =
                  (constraints.maxWidth / (180 + 12)).floor().clamp(1, 10);

              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: combined.length,
                itemBuilder: (ctx, i) {
                  final item = combined[i];
                  final isProcedure = item is Procedure;
                  final key = isProcedure ? 'p_${item.id}' : 'm_${item.id}';
                  final focusNode = _getGridFocusNode(key, i == 0);

                  return Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          final nextIdx = (i + 1) % combined.length;
                          final nextItem = combined[nextIdx];
                          final nextKey = nextItem is Procedure
                              ? 'p_${nextItem.id}'
                              : 'm_${nextItem.id}';
                          _getGridFocusNode(nextKey, false).requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowLeft) {
                          final prevIdx =
                              (i - 1 + combined.length) % combined.length;
                          final prevItem = combined[prevIdx];
                          final prevKey = prevItem is Procedure
                              ? 'p_${prevItem.id}'
                              : 'm_${prevItem.id}';
                          _getGridFocusNode(prevKey, false).requestFocus();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowDown) {
                          final nextIdx = i + crossAxisCount;
                          if (nextIdx < combined.length) {
                            final nextItem = combined[nextIdx];
                            final nextKey = nextItem is Procedure
                                ? 'p_${nextItem.id}'
                                : 'm_${nextItem.id}';
                            _getGridFocusNode(nextKey, false).requestFocus();
                          } else {
                            final topIdx = i % crossAxisCount;
                            final topItem = combined[topIdx];
                            final topKey = topItem is Procedure
                                ? 'p_${topItem.id}'
                                : 'm_${topItem.id}';
                            _getGridFocusNode(topKey, false).requestFocus();
                          }
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowUp) {
                          final prevIdx = i - crossAxisCount;
                          if (prevIdx >= 0) {
                            final prevItem = combined[prevIdx];
                            final prevKey = prevItem is Procedure
                                ? 'p_${prevItem.id}'
                                : 'm_${prevItem.id}';
                            _getGridFocusNode(prevKey, false).requestFocus();
                          } else {
                            int lastVisibleIdx = i;
                            while (lastVisibleIdx + crossAxisCount <
                                combined.length) {
                              lastVisibleIdx += crossAxisCount;
                            }
                            final lastItem = combined[lastVisibleIdx];
                            final lastKey = lastItem is Procedure
                                ? 'p_${lastItem.id}'
                                : 'm_${lastItem.id}';
                            _getGridFocusNode(lastKey, false).requestFocus();
                          }
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: ProductCard(
                      item: item,
                      focusNode: focusNode,
                      onTap: () {
                        if (isProcedure) {
                          widget.cart.addProcedure(item);
                          widget.onItemAddedToCart(key);
                        } else {
                          widget.onAddToGrid(item);
                        }
                      },
                      onSecondaryTap: isProcedure
                          ? (details) =>
                              _showProcedureContextMenu(context, details, item)
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showPatientQueueDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading:
                const Icon(Icons.app_registration, color: AppTheme.primary),
            title: const Text('Register New Patient'),
            subtitle: const Text('For first-time clinic visit'),
            onTap: () async {
              Navigator.pop(ctx);
              final patient = await showDialog<Patient>(
                context: context,
                builder: (ctx) => const PatientDialog(),
              );
              if (patient != null && context.mounted) {
                _showBookingDialog(context, patient);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_search, color: AppTheme.primary),
            title: const Text('Existing Patient'),
            subtitle: const Text('Search by name, phone or UHID'),
            onTap: () {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                builder: (ctx) => PatientSearchDialog(
                  showSkip: false,
                  onSelected: (p) => _showBookingDialog(context, p),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showBookingDialog(BuildContext context, Patient patient) {
    showDialog(
      context: context,
      builder: (ctx) => BookAppointmentDialog(patient: patient),
    );
  }

  void _showProcedureContextMenu(
      BuildContext context, TapDownDetails details, Procedure procedure) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.edit, color: AppTheme.primary),
            title: Text('Edit Procedure'),
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              showDialog(
                context: context,
                builder: (_) => ProcedureDialog(procedure: procedure),
              );
            });
          },
        ),
        PopupMenuItem(
          child: const ListTile(
            leading: Icon(Icons.delete, color: AppTheme.danger),
            title: Text('Delete Procedure'),
          ),
          onTap: () {
            _confirmDeleteProcedure(context, procedure);
          },
        ),
      ],
    );
  }

  void _confirmDeleteProcedure(BuildContext context, Procedure p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Procedure'),
        content: Text('Are you sure you want to delete "${p.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<ProcedureProvider>().deleteProcedure(p.id,
                  syncService: context.read<SyncService>());
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
