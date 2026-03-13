import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../theme/app_theme.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _aiService = AiService();
  final _keyController = TextEditingController();
  final _customModelController = TextEditingController();
  String _selectedModel = AiService.availableModels.first;
  bool _isLoading = true;
  bool _autoSelectBest = true; // Smart model selection toggle

  // Model capabilities description
  final Map<String, String> modelDescriptions = {
    'nvidia/nemotron-nano-12b-v2-vl:free': 'Multimodal vision - Best for image/OCR analysis',
    'hunter/hunter-alpha:free': 'Long context (1M tokens) - Best for stock prediction',
    'openrouter/healer-alpha:free': 'Omni-modal with vision & reasoning',
    'openrouter/free': 'Auto-selects fastest available free model',
    'arcee-ai/trinity-large-preview:free': 'Strong reasoning - Best for sales analysis',
    'stepfun/step-3.5-flash:free': 'Fast text processing',
    'qwen/qwen3-next-80b-a3b-instruct:free': 'Ultra-long context (262K tokens)',
    'google/gemini-2.5-flash-pro-exp': 'Fast Gemini model',
    'google/gemini-pro': 'Standard Gemini model',
    'anthropic/claude-3-haiku': 'Fast Claude model',
    'anthropic/claude-3-sonnet': 'Balanced Claude model',
    'openai/gpt-3.5-turbo': 'Fast GPT model',
    'openai/gpt-4o': 'Advanced GPT model',
    'meta-llama/llama-3-8b-instruct': 'Open source Llama model',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _aiService.loadConfig();
    setState(() {
      _keyController.text = _aiService.apiKey;
      _selectedModel = _aiService.selectedModel;

      // Fallback if the saved model is somehow not in the list anymore
      if (!AiService.availableModels.contains(_selectedModel)) {
        _selectedModel = 'Other (Custom)';
        _customModelController.text = _aiService.selectedModel;
      }
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API Key cannot be empty.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    String finalModel = _selectedModel;
    if (_selectedModel == 'Other (Custom)') {
      final customModel = _customModelController.text.trim();
      if (customModel.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom model ID cannot be empty.'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
      finalModel = customModel;
    }

    setState(() => _isLoading = true);
    await _aiService.saveConfig(key, finalModel);

    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved successfully.'),
        backgroundColor: AppTheme.success,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Configuration'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  Container(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Configuration',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Configure your OpenRouter API key and preferred AI model to generate business insights',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // API Key Section
                  _buildSectionHeader('API Configuration'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyController,
                    decoration: InputDecoration(
                      labelText: 'OpenRouter API Key',
                      hintText: 'sk-or-v1-...',
                      prefixIcon: const Icon(Icons.key, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 24),
                  
                  // Model Selection Section
                  _buildSectionHeader('Model Selection'),
                  const SizedBox(height: 12),
                  _buildModelSelectionCard(),
                  
                  // Smart Selection Section
                  if (_selectedModel != 'Other (Custom)') ...[
                    const SizedBox(height: 24),
                    _buildSmartSelectionSection(),
                  ],
                  
                  // Custom Model Section
                  if (_selectedModel == 'Other (Custom)') ...[
                    const SizedBox(height: 24),
                    _buildSectionHeader('Custom Model'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customModelController,
                      decoration: InputDecoration(
                        labelText: 'Custom Model ID',
                        hintText: 'e.g., arcee-ai/trinity-large-preview:free',
                        prefixIcon: const Icon(Icons.edit, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                  
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Save Configuration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ),
        );
  }
  
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
  
  Widget _buildModelSelectionCard() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Free Models Section
          if (AiService.availableModels.where((m) => m.contains(':free')).isNotEmpty)
            _buildModelSection(
              '🎯 FREE MODELS',
              Colors.green,
              AiService.availableModels.where((m) => m.contains(':free')),
            ),
          
          // Divider
          if (AiService.availableModels.where((m) => m.contains(':free')).isNotEmpty &&
              AiService.availableModels.where((m) => !m.contains(':free')).isNotEmpty)
            Container(
              height: 1,
              color: Colors.grey[200],
              margin: const EdgeInsets.symmetric(horizontal: 16),
            ),
          
          // Your Models Section
          if (AiService.availableModels.where((m) => !m.contains(':free')).isNotEmpty)
            _buildModelSection(
              '⚡ YOUR MODELS',
              Colors.blue,
              AiService.availableModels.where((m) => !m.contains(':free')),
            ),
        ],
      ),
    );
  }
  
  Widget _buildModelSection(String title, Color color, Iterable<String> models) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: models.length,
          itemBuilder: (context, index) {
            final model = models.elementAt(index);
            final isSelected = _selectedModel == model;
            return RadioListTile<String>(
              title: Text(
                model,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              subtitle: modelDescriptions.containsKey(model)
                  ? Text(
                      modelDescriptions[model]!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    )
                  : null,
              value: model,
              groupValue: _selectedModel,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedModel = value);
                }
              },
              activeColor: Theme.of(context).colorScheme.primary,
              secondary: Icon(
                Icons.circle,
                size: 12,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[400],
              ),
            );
          },
        ),
      ],
    );
  }
  
  Widget _buildSmartSelectionSection() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.autorenew, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'Smart Model Selection',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How it works:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                _buildRuleItem('📊 Sales/Analysis queries', 'Arcee Trinity (strong reasoning)'),
                _buildRuleItem('📈 Stock/Prediction queries', 'Hunter Alpha (1M context)'),
                _buildRuleItem('🖼️ Image uploads', 'NVIDIA Nemotron (multimodal)'),
                _buildRuleItem('💬 Simple queries', 'openrouter/free (fastest)'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                 child: Text(
                   '💡 Tip: The AI will automatically choose the best model for each query type, optimizing for both accuracy and cost.',
                   style: TextStyle(
                     fontSize: 12,
                     fontStyle: FontStyle.italic,
                     color: Colors.grey[700],
                   ),
                 ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRuleItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
