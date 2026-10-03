import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../shared/providers/auth_provider.dart';
import '../shared/services/objectbox_service.dart';

class AdminPinSetupScreen extends StatefulWidget {
  const AdminPinSetupScreen({super.key});

  @override
  State<AdminPinSetupScreen> createState() => _AdminPinSetupScreenState();
}

class _AdminPinSetupScreenState extends State<AdminPinSetupScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pin.text;
    if (!RegExp(r'^\d{4}$|^\d{6}$').hasMatch(pin) || pin == '0000' ||
        pin == '1111' || pin == '123456' || pin == '000000' || pin == '111111') {
      setState(() => _error = 'Choose a 4-digit or 6-digit PIN.');
      return;
    }
    if (pin != _confirm.text) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    final admin = ObjectBoxService.instance.userBox.getAll()
        .where((u) => u.role.toLowerCase() == 'admin' &&
            (u.pin == 'SETUP_REQUIRED' || u.pin == '1234'))
        .firstOrNull;
    if (admin == null) return;
    context.read<AuthProvider>().updatePin(admin.id, pin, actor: admin);
  }

  @override
  Widget build(BuildContext context) {
    Widget pinField(String label, TextEditingController controller) => TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        );
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Set the administrator PIN',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('This Hub needs a new PIN before staff can sign in.'),
              const SizedBox(height: 24),
              pinField('New 4 or 6-digit PIN', _pin),
              const SizedBox(height: 12),
              pinField('Confirm PIN', _confirm),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('Save PIN')),
            ]),
          ),
        ),
      ),
    );
  }
}
