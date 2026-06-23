import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../shared/services/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _keyController = TextEditingController();
  bool _isLoading = false;
  String _activationError = '';

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _handleActivation() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _activationError = 'Please enter a key');
      return;
    }

    setState(() {
      _isLoading = true;
      _activationError = '';
    });

    final success = await SubscriptionService.instance.activateLicense(key);

    setState(() => _isLoading = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MediPoss Activated successfully!')),
      );
      Navigator.of(context).pop(); // Go back to where they were
    } else {
      setState(() => _activationError = 'Invalid key. Check internet & try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sub = context.watch<SubscriptionService>();
    final upi = sub.upiId;

    final upiPayUri = upi.isNotEmpty 
        ? 'upi://pay?pa=$upi&pn=MediPoss&cu=INR' 
        : '';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                'Upgrade to Premium',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ).animate().fadeIn(duration: 400.ms),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Unlock real-time cloud synchronizations and advanced clinic features.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Plan Feature List Box
            _buildFeatureListCard(theme, isDark),
            const SizedBox(height: 24),

            // Scan QR / Payment details
            if (upiPayUri.isNotEmpty) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: QrImageView(
                    data: upiPayUri,
                    version: QrVersions.auto,
                    size: 180.0,
                  ),
                ),
              ).animate().scale(delay: 200.ms, duration: 450.ms, curve: Curves.elasticOut),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Scan to Pay via UPI',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Input Activation Key Form
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enter Activation Key',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'MP-PRO-xxxx-xxxx',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_activationError.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _activationError,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleActivation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Activate Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureListCard(ThemeData theme, bool isDark) {
    return Column(
      children: [
        _buildTierHeader('PRO PLAN', '₹2,999 / Year', theme, isDark, [
          'Real-time Firestore Internet Sync',
          'Google Drive Cloud Backup',
          'Advanced Analysis & KPIs Modules',
          'Multi-device pairing over Web',
        ], theme.colorScheme.primary),
        const SizedBox(height: 16),
        _buildTierHeader('ENTERPRISE PLAN', '₹5,999 / Year', theme, isDark, [
          'Everything in Pro Plan',
          'Clinical OPD Queue & Patient Management',
          'Regulatory Compliance Audit Logging',
          'Custom Prescribing Doctor Setup',
        ], const Color(0xFF10B981)), // Emerald Green
      ],
    );
  }

  Widget _buildTierHeader(String name, String price, ThemeData theme, bool isDark, List<String> bulletPoints, Color tierColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tierColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: tierColor,
                ),
              ),
              Text(
                price,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bulletPoints.map((pt) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: tierColor, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    pt,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
