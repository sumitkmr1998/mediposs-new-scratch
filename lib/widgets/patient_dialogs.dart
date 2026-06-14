import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../shared/models/patient.dart';
import '../shared/models/doctor.dart';
import '../shared/models/appointment.dart';
import '../shared/providers/patient_provider.dart';
import '../shared/providers/sales_provider.dart';
import '../shared/providers/opd_provider.dart';
import '../shared/providers/auth_provider.dart';
import '../shared/services/sync_service.dart';
import '../theme/app_theme.dart';

// ─── Shared Patient Registration Dialog ───────────────────────────────────────
class PatientDialog extends StatefulWidget {
  final Patient? patient;
  const PatientDialog({super.key, this.patient});

  @override
  State<PatientDialog> createState() => _PatientDialogState();
}

class _PatientDialogState extends State<PatientDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _gender = 'Male';
  final List<String> _genders = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
    if (widget.patient != null) {
      _nameCtrl.text = widget.patient!.name;
      _phoneCtrl.text = widget.patient!.phone;
      _addressCtrl.text = widget.patient!.address;
      _gender = widget.patient!.gender;
      _ageCtrl.text = widget.patient!.age.toString();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyM) {
      setState(() => _gender = 'Male');
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() => _gender = 'Female');
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      final idx = _genders.indexOf(_gender);
      setState(() => _gender = _genders[(idx + 1) % _genders.length]);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      final idx = _genders.indexOf(_gender);
      setState(() =>
          _gender = _genders[(idx - 1 + _genders.length) % _genders.length]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.patient != null;
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: _handleKeyPress,
      child: AlertDialog(
        title: Text(isEdit ? 'Edit Patient' : 'New Patient'),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameCtrl,
                  autofocus: !isEdit,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: Icon(Icons.person_outline),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _gender,
                        decoration: const InputDecoration(
                          labelText: 'Gender (M/F keys)',
                          isDense: true,
                        ),
                        items: _genders
                            .map((g) =>
                                DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (v) => setState(() => _gender = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _ageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Age',
                          prefixIcon: Icon(Icons.cake_outlined),
                          suffixText: 'yrs',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_nameCtrl.text.trim().isEmpty) return;
              final provider = context.read<PatientProvider>();
              final p =
                  widget.patient ?? Patient(uhid: '', name: '', gender: 'Male');
              p.name = _nameCtrl.text.trim();
              p.phone = _phoneCtrl.text.trim();
              p.gender = _gender;
              p.age = int.tryParse(_ageCtrl.text) ?? 0;
              p.address = _addressCtrl.text.trim();
              final sync = context.read<SyncService>();
              final saved = provider.savePatient(p, sync, context.read<AuthProvider>().currentUser);
              Navigator.pop(context, saved);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                      Text(isEdit ? 'Patient updated' : 'Patient registered'),
                  backgroundColor: AppTheme.success,
                ),
              );
            },
            child: Text(isEdit ? 'Update' : 'Register'),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Patient Search Dialog ─────────────────────────────────────────────
class PatientSearchDialog extends StatefulWidget {
  final Function(Patient) onSelected;
  final Function(Appointment)? onAppointmentSelected;
  final bool limitToTodayOpd;
  final bool showSkip;

  const PatientSearchDialog({
    super.key,
    required this.onSelected,
    this.onAppointmentSelected,
    this.limitToTodayOpd = false,
    this.showSkip = true,
  });

  @override
  State<PatientSearchDialog> createState() => _PatientSearchDialogState();
}

class _PatientSearchDialogState extends State<PatientSearchDialog> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.toLowerCase();

    if (widget.limitToTodayOpd) {
      final opd = context.watch<OpdProvider>();
      final todayQueue = opd.todayQueue; // already sorted by tokenNumber
      final filteredAppts = todayQueue.where((a) {
        return a.patientName.toLowerCase().contains(query) ||
            a.patientPhone.contains(query) ||
            a.tokenNumber.toString().contains(query) ||
            a.doctorName.toLowerCase().contains(query);
      }).toList();

      if (_selectedIndex >= filteredAppts.length && filteredAppts.isNotEmpty) {
        _selectedIndex = 0;
      }

      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () {
            if (filteredAppts.isNotEmpty) {
              setState(() =>
                  _selectedIndex = (_selectedIndex + 1) % filteredAppts.length);
            }
          },
          const SingleActivator(LogicalKeyboardKey.arrowUp): () {
            if (filteredAppts.isNotEmpty) {
              setState(() => _selectedIndex =
                  (_selectedIndex - 1 + filteredAppts.length) % filteredAppts.length);
            }
          },
          const SingleActivator(LogicalKeyboardKey.enter): () {
            if (filteredAppts.isNotEmpty) {
              final selectedAppt = filteredAppts[_selectedIndex];
              Navigator.pop(context);
              if (widget.onAppointmentSelected != null) {
                widget.onAppointmentSelected!(selectedAppt);
              } else {
                final patients = context.read<PatientProvider>().patients;
                final p = patients.where((x) => x.id == selectedAppt.patientId).firstOrNull ??
                    (Patient(uhid: '', name: selectedAppt.patientName, phone: selectedAppt.patientPhone, gender: 'Male')..id = selectedAppt.patientId);
                widget.onSelected(p);
              }
            }
          },
        },
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_search, color: AppTheme.primary),
              SizedBox(width: 12),
              Text('Select Patient from OPD Queue'),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchCtrl,
                  focusNode: _focusNode,
                  decoration: const InputDecoration(
                    hintText: 'Search by Name, Phone, Doctor or Token...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (val) => setState(() => _selectedIndex = 0),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4),
                  child: filteredAppts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_off_outlined,
                                  size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              Text('No matching patient found in today\'s queue.',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredAppts.length,
                          itemBuilder: (ctx, i) {
                            final a = filteredAppts[i];
                            final isSelected = i == _selectedIndex;
                            return Container(
                              color: isSelected
                                  ? AppTheme.primary.withOpacity(0.1)
                                  : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppTheme.primary.withOpacity(0.1),
                                  child: Text('#${a.tokenNumber}',
                                      style: const TextStyle(
                                          color: AppTheme.primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ),
                                title: Text(a.patientName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text('Dr. ${a.doctorName} • Status: ${a.status}'),
                                trailing: Text(a.patientPhone,
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey)),
                                onTap: () {
                                  Navigator.pop(context);
                                  if (widget.onAppointmentSelected != null) {
                                    widget.onAppointmentSelected!(a);
                                  } else {
                                    final patients = context.read<PatientProvider>().patients;
                                    final p = patients.where((x) => x.id == a.patientId).firstOrNull ??
                                        (Patient(uhid: '', name: a.patientName, phone: a.patientPhone, gender: 'Male')..id = a.patientId);
                                    widget.onSelected(p);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            if (widget.showSkip)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip / Walk-in'),
              ),
          ],
        ),
      );
    }

    final patients = context.watch<PatientProvider>().patients;
    final filtered = patients.where((p) {
      return p.name.toLowerCase().contains(query) ||
          p.phone.contains(query) ||
          p.address.toLowerCase().contains(query) ||
          p.uhid.toLowerCase().contains(query);
    }).toList();

    if (_selectedIndex >= filtered.length && filtered.isNotEmpty) {
      _selectedIndex = 0;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (filtered.isNotEmpty) {
            setState(
                () => _selectedIndex = (_selectedIndex + 1) % filtered.length);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (filtered.isNotEmpty) {
            setState(() => _selectedIndex =
                (_selectedIndex - 1 + filtered.length) % filtered.length);
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (filtered.isNotEmpty) {
            widget.onSelected(filtered[_selectedIndex]);
            Navigator.pop(context);
          }
        },
      },
      child: AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_search, color: AppTheme.primary),
            SizedBox(width: 12),
            Text('Select Patient'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: const BoxConstraints(maxWidth: 450),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _searchCtrl,
                focusNode: _focusNode,
                decoration: const InputDecoration(
                  hintText: 'Search by Name, Phone, Address or UHID...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (val) => setState(() => _selectedIndex = 0),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: filtered.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_off_outlined,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No matching patient found.',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) {
                          final p = filtered[i];
                          final isSelected = i == _selectedIndex;
                          return Container(
                            color: isSelected
                                ? AppTheme.primary.withOpacity(0.1)
                                : null,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppTheme.primary.withOpacity(0.1),
                                child: Text(p.name[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: AppTheme.primary)),
                              ),
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text('${p.phone} • ${p.address}'),
                              trailing: Text(p.uhid,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                              onTap: () {
                                // Pop dialog FIRST so the outer context stays valid,
                                // then call onSelected to open the booking dialog
                                Navigator.pop(context);
                                widget.onSelected(p);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.showSkip)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip / Walk-in'),
            ),
        ],
      ),
    );
  }
}

// ─── Shared Book Appointment Dialog ───────────────────────────────────────────
class BookAppointmentDialog extends StatefulWidget {
  final Patient patient;
  const BookAppointmentDialog({super.key, required this.patient});

  @override
  State<BookAppointmentDialog> createState() => _BookAppointmentDialogState();
}

class _BookAppointmentDialogState extends State<BookAppointmentDialog> {
  Doctor? _selectedDoctor;
  String _paymentMethod = 'cash';

  @override
  Widget build(BuildContext context) {
    final opd = context.watch<OpdProvider>();
    final doctors = opd.activeDoctors;

    // Guard: if the doctors list was refreshed and no longer contains the
    // selected doctor (stale reference after sync), reset to null to avoid
    // the 'DropdownButton exactly one item' crash.
    if (_selectedDoctor != null &&
        !doctors.any((d) => d.id == _selectedDoctor!.id)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => setState(() => _selectedDoctor = null));
    }
    // Re-resolve selected doctor from the current doctors list by ID
    final resolvedDoctor = _selectedDoctor == null
        ? null
        : doctors.where((d) => d.id == _selectedDoctor!.id).firstOrNull;

    return AlertDialog(
      title: Text('Book for ${widget.patient.name}'),
      content: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('UHID: ${widget.patient.uhid}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            if (doctors.isEmpty)
              const Text('No active doctors.',
                  style: TextStyle(color: AppTheme.warning))
            else
              DropdownButtonFormField<Doctor>(
                value: resolvedDoctor,
                decoration: const InputDecoration(
                  labelText: 'Select Doctor *',
                  prefixIcon: Icon(Icons.medical_services_outlined),
                  isDense: true,
                ),
                items: doctors
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                              'Dr. ${d.name}  •  ₹${d.consultationFee.toStringAsFixed(0)}'),
                        ))
                    .toList(),
                onChanged: (d) => setState(() => _selectedDoctor = d),
              ),
            if (resolvedDoctor != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(resolvedDoctor.specialization,
                        style: const TextStyle(color: Colors.grey)),
                    Text(
                        '₹${resolvedDoctor.consultationFee.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('Payment Mode *',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7B8D))),
              const SizedBox(height: 8),
              Row(
                children: [
                  _PaymentChip(
                    icon: Icons.payments_rounded,
                    label: 'Cash',
                    value: 'cash',
                    selected: _paymentMethod,
                    color: AppTheme.success,
                    onTap: () => setState(() => _paymentMethod = 'cash'),
                  ),
                  const SizedBox(width: 8),
                  _PaymentChip(
                    icon: Icons.qr_code_2_rounded,
                    label: 'UPI',
                    value: 'upi',
                    selected: _paymentMethod,
                    color: AppTheme.primary,
                    onTap: () => setState(() => _paymentMethod = 'upi'),
                  ),
                  const SizedBox(width: 8),
                  _PaymentChip(
                    icon: Icons.credit_card_rounded,
                    label: 'Card',
                    value: 'card',
                    selected: _paymentMethod,
                    color: AppTheme.accent,
                    onTap: () => setState(() => _paymentMethod = 'card'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: resolvedDoctor == null
              ? null
              : () async {
                  final opd = context.read<OpdProvider>();
                  final appt = await opd.createAppointment(
                    patientId: widget.patient.id,
                    patientName: widget.patient.name,
                    patientPhone: widget.patient.phone,
                    doctorId: resolvedDoctor.id,
                    doctorName: resolvedDoctor.name,
                    consultationFee: resolvedDoctor.consultationFee,
                    paymentMethod: _paymentMethod,
                    syncService: context.read<SyncService>(),
                    actor: context.read<AuthProvider>().currentUser,
                    salesProvider: context.read<SalesProvider>(),
                  );
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Token #${appt.tokenNumber} booked for ${widget.patient.name}'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                },
          child: const Text('Book Appointment'),
        ),
      ],
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String selected;
  final Color color;
  final VoidCallback onTap;

  const _PaymentChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Expanded(
      child: Material(
        color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: isSelected ? color : Colors.grey, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? color : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
