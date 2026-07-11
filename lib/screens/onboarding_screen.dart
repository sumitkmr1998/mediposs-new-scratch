import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/services/subscription_service.dart';
import '../shared/services/objectbox_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isTerminalMode = false;

  // Configuration Form Controllers
  final _formKey = GlobalKey<FormState>();
  final _storeNameController = TextEditingController(text: 'MediPoss Pharmacy');
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _gstController = TextEditingController();

  // License Key Controller
  final _keyController = TextEditingController();
  String _activationError = '';

  @override
  void dispose() {
    _pageController.dispose();
    _storeNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _gstController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentStep == 2) {
      if (!_formKey.currentState!.validate()) return;
      _saveShopDetails();
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _prevPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _saveShopDetails() {
    final box = ObjectBoxService.instance.settingsBox;
    final current = ObjectBoxService.instance.settings;
    
    current.storeName = _storeNameController.text.trim();
    current.storePhone = _phoneController.text.trim();
    current.storeAddress = _addressController.text.trim();
    current.gstNumber = _gstController.text.trim();
    
    box.put(current);
    debugPrint('OnboardingScreen: Saved shop configurations locally.');
  }

  Future<void> _finishTerminalOnboarding() async {
    setState(() => _isLoading = true);
    try {
      final box = ObjectBoxService.instance.settingsBox;
      final current = ObjectBoxService.instance.settings;
      current.isWindowsClient = true;
      box.put(current);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isTerminalMode', true);

      await SubscriptionService.instance.setFirstLaunchCompleted();
    } catch (e) {
      debugPrint('OnboardingScreen Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
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

    if (success) {
      await SubscriptionService.instance.setFirstLaunchCompleted();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MediPoss Activated successfully!')),
        );
      }
    } else {
      setState(() => _activationError = 'Invalid key. Check internet & try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Header progress indicator
              _buildStepProgressIndicator(theme),
              const SizedBox(height: 24),
              
              // Carousel content
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (idx) {
                    setState(() => _currentStep = idx);
                  },
                  children: [
                    _buildStepWelcome(theme, isDark),
                    _buildStepModeSelection(theme, isDark),
                    _buildStepShopConfig(theme, isDark),
                    _buildStepActivation(theme, isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepProgressIndicator(ThemeData theme) {
    return Row(
      children: List.generate(4, (idx) {
        final active = _currentStep >= idx;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 6,
            decoration: BoxDecoration(
              color: active ? theme.colorScheme.primary : (theme.brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[300]),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepModeSelection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select App Mode',
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ).animate().fadeIn(duration: 300.ms),
        const SizedBox(height: 8),
        Text(
          'Choose how this device will interact with your pharmacy database.',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Column(
            children: [
              _buildModeCard(
                theme: theme,
                isDark: isDark,
                title: 'Standalone Hub Mode',
                description: 'This device hosts the primary database and serves other terminals. Recommended for the main PC or primary tablet.',
                icon: Icons.dns_rounded,
                selected: !_isTerminalMode,
                onTap: () => setState(() => _isTerminalMode = false),
              ),
              const SizedBox(height: 16),
              _buildModeCard(
                theme: theme,
                isDark: isDark,
                title: 'Companion Terminal Mode',
                description: 'This device acts as a client/terminal, connecting to a primary Hub device on your local network or cloud.',
                icon: Icons.phonelink_rounded,
                selected: _isTerminalMode,
                onTap: () => setState(() => _isTerminalMode = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton(
              onPressed: _prevPage,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                label: _isTerminalMode ? 'Finish & Start Pairing' : 'Continue',
                onTap: () async {
                  if (_isTerminalMode) {
                    await _finishTerminalOnboarding();
                  } else {
                    _nextPage();
                  }
                },
                theme: theme,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required ThemeData theme,
    required bool isDark,
    required String title,
    required String description,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected 
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : (isDark ? const Color(0xFF1E293B) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 36,
              color: selected ? theme.colorScheme.primary : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: selected ? theme.colorScheme.primary : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStepWelcome(ThemeData theme, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.local_pharmacy_rounded, color: theme.colorScheme.primary, size: 84)
            .animate()
            .scale(delay: 200.ms, duration: 450.ms, curve: Curves.elasticOut),
        const SizedBox(height: 24),
        Text(
          'Welcome to MediPoss',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ).animate().fadeIn(duration: 400.ms),
        const SizedBox(height: 12),
        Text(
          'Your all-in-one Smart Medical POS and Warehouse inventory solution with live real-time cloud synchronizations.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            height: 1.5,
          ),
        ).animate().fadeIn(delay: 150.ms, duration: 400.ms),
        const SizedBox(height: 48),
        _buildActionButton(label: 'Get Started', onTap: _nextPage, theme: theme),
      ],
    );
  }

  Widget _buildStepShopConfig(ThemeData theme, bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Configure Pharmacy',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ).animate().fadeIn(duration: 300.ms),
          const SizedBox(height: 8),
          Text(
            'Enter your retail pharmacy details for receipt prints and registration.',
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView(
              children: [
                _buildTextField(
                  label: 'Pharmacy / Shop Name *',
                  controller: _storeNameController,
                  icon: Icons.store_rounded,
                  validator: (v) => v!.isEmpty ? 'Name required' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Contact Number *',
                  controller: _phoneController,
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (v) => v!.isEmpty ? 'Phone required' : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'Shop Address',
                  controller: _addressController,
                  icon: Icons.location_on_rounded,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  label: 'GSTIN Number (Optional)',
                  controller: _gstController,
                  icon: Icons.receipt_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(
                onPressed: _prevPage,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(label: 'Continue', onTap: _nextPage, theme: theme),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepActivation(ThemeData theme, bool isDark) {
    final sub = context.watch<SubscriptionService>();
    final upi = sub.upiId;

    final upiPayUri = upi.isNotEmpty 
        ? 'upi://pay?pa=$upi&pn=MediPoss&cu=INR' 
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Activate License',
          style: GoogleFonts.outfit(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ).animate().fadeIn(duration: 300.ms),
        const SizedBox(height: 8),
        Text(
          'Enter activation key or scan UPI QR code directly below to make a payment and receive your key.',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
        const SizedBox(height: 20),
        
        // Scan QR Area
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (upiPayUri.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: QrImageView(
                      data: upiPayUri,
                      version: QrVersions.auto,
                      size: 160.0,
                    ),
                  ).animate().scale(delay: 100.ms, duration: 300.ms),
                  const SizedBox(height: 8),
                  Text(
                    'Scan to Pay via UPI',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[600], fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Loading payment details...')),
                  ),
                ],
                
                // Key Input
                _buildTextField(
                  label: 'Activation Key',
                  controller: _keyController,
                  icon: Icons.vpn_key_rounded,
                  hintText: 'Enter MP-PRO-xxxx-xxxx',
                ),
                if (_activationError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _activationError,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton(
              onPressed: _prevPage,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleActivation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Activate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _skipOnboarding,
            child: Text(
              'Skip Activation (Continue with Free Tier)',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _skipOnboarding() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Use Free Tier?'),
        content: const Text(
          'Without an activation key, cloud real-time sync, cloud backups, and advanced analysis features will be locked. You can still use the core offline POS features.\n\nYou can always enter a license key later in settings to upgrade.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue Free'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SubscriptionService.instance.setFirstLaunchCompleted();
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hintText,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, color: Colors.grey[500]),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildActionButton({required String label, required VoidCallback onTap, required ThemeData theme}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minimumSize: const Size(double.infinity, 54),
      ),
      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
