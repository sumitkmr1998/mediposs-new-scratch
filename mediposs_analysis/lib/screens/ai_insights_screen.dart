import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../models/medicine.dart';

import '../providers/hub_provider.dart';
import '../services/ai_service.dart';
import '../services/chat_db_service.dart';
import '../models/chat_thread.dart';
import '../models/chat_message.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_chart_widget.dart';

class AiInsightsScreen extends StatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  State<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends State<AiInsightsScreen> {
  final _aiService = AiService();
  final _controller = TextEditingController();
  final _uuid = const Uuid();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _imagePicker = ImagePicker();

  List<ChatMessage> _messages = [];
  List<ChatThread> _threads = [];
  List<ChatThread> _filteredThreads = [];
  String? _currentThreadId;
  bool _isTyping = false;
  bool _isLoadingThreads = true;
  String? _attachedImagePath;
  String? _attachedExcelPath;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    final threads = await ChatDbService.instance.getThreads();
    setState(() {
      _threads = threads;
      _filteredThreads = threads;
      _isLoadingThreads = false;
    });
  }

  void _filterThreads(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredThreads = _threads;
      } else {
        _filteredThreads = _threads
            .where((thread) => 
                thread.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _loadMessages(String threadId) async {
    setState(() => _isTyping = true);
    final msgs = await ChatDbService.instance.getMessages(threadId);
    setState(() {
      _currentThreadId = threadId;
      _messages = msgs;
      _isTyping = false;
    });
    if (!mounted) return;
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  void _startNewChat() {
    setState(() {
      _currentThreadId = null;
      _attachedImagePath = null;
      _messages = [
        ChatMessage(
          id: _uuid.v4(),
          threadId: 'temp',
          role: 'ai',
          content:
              '👋 Welcome to Mediposs AI Analysis! I can help you analyze sales trends, identify dead stock, and even **process purchase bills.**\n\nTry uploading a bill photo using the 📎 button to automatically update your warehouse inventory!',
          createdAt: DateTime.now(),
        ),
      ];
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _attachedImagePath = picked.path;
        _attachedExcelPath = null; // Can't attach both image and Excel
      });
    }
  }

  Future<void> _pickExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx'],
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          setState(() {
            _attachedExcelPath = path;
            _attachedImagePath = null; // Can't attach both image and Excel
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking Excel file: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    final imagePath = _attachedImagePath;
    final excelPath = _attachedExcelPath;
    
    if (text.isEmpty && imagePath == null && excelPath == null) return;

    final hub = context.read<HubProvider>();

    _controller.clear();
    setState(() {
      _attachedImagePath = null;
      _attachedExcelPath = null;
    });

    if (_currentThreadId == null) {
      String title;
      if (excelPath != null) {
        title = '📊 ${text.isNotEmpty ? (text.length > 15 ? '${text.substring(0, 15)}...' : text) : 'Excel Analysis'}';
      } else if (imagePath != null) {
        title = '📷 ${text.isNotEmpty ? (text.length > 15 ? '${text.substring(0, 15)}...' : text) : 'Bill Image'}';
      } else {
        title = text.length > 20 ? '${text.substring(0, 20)}...' : text;
      }
      
      _currentThreadId = await ChatDbService.instance.createThread(title);
      _messages.clear();
      // Add welcome message for new thread
      _messages.add(ChatMessage(
        id: _uuid.v4(),
        threadId: _currentThreadId!,
        role: 'ai',
        content: '👋 Welcome to Mediposs AI Analysis! I can help you analyze sales trends, identify dead stock, process purchase bills, or **analyze Excel files.**\n\nTry uploading a bill photo, Excel file, or ask questions about your inventory!',
        createdAt: DateTime.now(),
      ));
      _loadThreads();
    }

    // Build user message content
    String userContent = text;
    if (imagePath != null) {
      userContent = '${text.isNotEmpty ? text : "Analyze this bill"}\n📷 [Image attached]';
    } else if (excelPath != null) {
      userContent = '${text.isNotEmpty ? text : "Analyze this Excel file"}\n📊 [Excel file attached]';
    }

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      threadId: _currentThreadId!,
      role: 'user',
      content: userContent,
      imagePath: imagePath,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isTyping = true;
    });

    await ChatDbService.instance.saveMessage(userMsg);

    await _aiService.loadConfig();
    if (!_aiService.isConfigured) {
      if (!mounted) return;
      final errorMsg = ChatMessage(
        id: _uuid.v4(),
        threadId: _currentThreadId!,
        role: 'system',
        content:
            '⚠️ Please configure your OpenRouter API Key in the Settings (gear icon on the dashboard) before requesting insights.',
        createdAt: DateTime.now(),
      );

      await ChatDbService.instance.saveMessage(errorMsg);
      setState(() {
        _messages.add(errorMsg);
        _isTyping = false;
      });
      return;
    }

    // Call AI with appropriate method based on attachment type
    if (excelPath != null) {
      final excelFile = File(excelPath);
      final response = await _aiService.analyzeExcel(
        text,
        excelFile,
        hub.sales,
        hub.medicines,
        _messages,
      );
      _addAiResponse(response);
    } else if (imagePath != null) {
      final response = await _aiService.askAiWithImage(
        text,
        imagePath,
        hub.sales,
        hub.medicines,
        _messages,
      );
      _addAiResponse(response);
    } else {
      // Use streaming for better perceived performance
      final stream = _aiService.askAiStream(
        query: text,
        sales: hub.sales,
        medicines: hub.medicines,
        conversationHistory: _messages,
      );
      
      String streamedResponse = '';
      await for (final chunk in stream) {
        if (!mounted) return;
        streamedResponse += chunk;
        setState(() {
          // Update the last AI message with new content
          final lastMsg = _messages.lastWhere(
            (m) => m.role == 'ai',
            orElse: () {
              final msg = ChatMessage(
                id: _uuid.v4(),
                threadId: _currentThreadId!,
                role: 'ai',
                content: streamedResponse,
                createdAt: DateTime.now(),
              );
              _messages.add(msg);
              return msg;
            },
          );
          lastMsg.content = streamedResponse;
        });
      }
      
      // Save the complete message to database
      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        threadId: _currentThreadId!,
        role: 'ai',
        content: streamedResponse,
        createdAt: DateTime.now(),
      );
      await ChatDbService.instance.saveMessage(aiMsg);
    }

    if (!mounted) return;
    setState(() => _isTyping = false);
  }

  void _addAiResponse(String response) async {
    final aiMsg = ChatMessage(
      id: _uuid.v4(),
      threadId: _currentThreadId!,
      role: 'ai',
      content: response,
      createdAt: DateTime.now(),
    );

    await ChatDbService.instance.saveMessage(aiMsg);

    if (!mounted) return;

    setState(() {
      _messages.add(aiMsg);
      _isTyping = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Ask AI'),
        backgroundColor: AppTheme.info.withValues(alpha: 0.1),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Open Chat History',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: 'New Chat',
            onPressed: _startNewChat,
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              color: AppTheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chat History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_threads.length} conversations',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search chats...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: _filterThreads,
              ),
            ),
            
            // Chat list
            Expanded(
              child: _isLoadingThreads
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredThreads.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 48,
                                color: AppTheme.textTertiary.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No previous chats'
                                    : 'No chats found for "$_searchQuery"',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredThreads.length,
                          itemBuilder: (context, index) {
                            final thread = _filteredThreads[index];
                            final isSelected = thread.id == _currentThreadId;
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary.withValues(alpha: 0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.chat_bubble_outline,
                                  color: isSelected
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                ),
                                title: Text(
                                  thread.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  '${thread.updatedAt.day}/${thread.updatedAt.month}/${thread.updatedAt.year}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                selected: isSelected,
                                onTap: () {
                                  _loadMessages(thread.id);
                                  Navigator.pop(context); // Close drawer
                                },
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: AppTheme.danger,
                                  ),
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Chat'),
                                        content: Text(
                                            'Are you sure you want to delete "${thread.title}"?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.danger,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    
                                    if (confirmed == true) {
                                      await ChatDbService.instance
                                          .deleteThread(thread.id);
                                      if (_currentThreadId == thread.id) {
                                        _startNewChat();
                                      }
                                      _loadThreads();
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
            
            // Clear all chats button
            if (_threads.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Clear All Chats'),
                        content: const Text(
                            'Are you sure you want to delete all chat history? This action cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.danger,
                            ),
                            child: const Text('Clear All'),
                          ),
                        ],
                      ),
                    );
                    
                    if (confirmed == true) {
                      for (final thread in _threads) {
                        await ChatDbService.instance.deleteThread(thread.id);
                      }
                      _startNewChat();
                      _loadThreads();
                    }
                  },
                  icon: Icon(
                    Icons.delete_sweep,
                    size: 18,
                    color: AppTheme.danger,
                  ),
                  label: Text(
                    'Clear All Chats',
                    style: TextStyle(color: AppTheme.danger),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty && _currentThreadId == null
                ? const Center(child: Text('Start a new conversation'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg.role == 'user';
                      return _ChatBubble(
                        text: msg.content,
                        isUser: isUser,
                        imagePath: msg.imagePath,
                      );
                    },
                  ),
          ),
          if (_isTyping)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'AI is thinking...',
                    style: TextStyle(
                      color: AppTheme.info,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Image preview strip
          if (_attachedImagePath != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surface,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_attachedImagePath!),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '📷 Bill image attached',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.danger),
                    onPressed: () => setState(() => _attachedImagePath = null),
                  ),
                ],
              ),
            ),

          // Excel file preview strip
          if (_attachedExcelPath != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surface,
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.table_chart,
                      color: AppTheme.primary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📊 Excel file attached',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          _attachedExcelPath!.split('\\').last,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.danger),
                    onPressed: () => setState(() => _attachedExcelPath = null),
                  ),
                ],
              ),
            ),

          // Input bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                // Image attachment button
                IconButton(
                  icon: Icon(
                    Icons.image,
                    color: _attachedImagePath != null
                        ? AppTheme.success
                        : AppTheme.primary,
                  ),
                  tooltip: 'Attach bill image',
                  onPressed: _isTyping ? null : _pickImage,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  ),
                ),
                const SizedBox(width: 8),
                // Excel attachment button
                IconButton(
                  icon: Icon(
                    Icons.table_chart,
                    color: _attachedExcelPath != null
                        ? AppTheme.success
                        : AppTheme.primary,
                  ),
                  tooltip: 'Attach Excel file',
                  onPressed: _isTyping ? null : _pickExcel,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: _attachedImagePath != null
                          ? 'Add a message about this bill...'
                          : _attachedExcelPath != null
                              ? 'Ask about the Excel data...'
                              : 'e.g., What should I restock next?',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: _isTyping ? null : _sendMessage,
                  icon: const Icon(Icons.send),
                  color: AppTheme.primary,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final String? imagePath;

  const _ChatBubble({required this.text, required this.isUser, this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primary : AppTheme.background,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser
                ? const Radius.circular(0)
                : const Radius.circular(16),
            bottomLeft: !isUser
                ? const Radius.circular(0)
                : const Radius.circular(16),
          ),
          border: isUser ? null : Border.all(color: Colors.grey.shade300),
        ),
        child: _buildParsedContent(context),
      ),
    );
  }

  Widget _buildParsedContent(BuildContext context) {
    final children = <Widget>[];

    // Show attached image thumbnail for user messages
    if (isUser && imagePath != null && imagePath!.isNotEmpty) {
      final file = File(imagePath!);
      if (file.existsSync()) {
        children.add(
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(file, width: 200, height: 150, fit: BoxFit.cover),
          ),
        );
        children.add(const SizedBox(height: 8));
      }
    }

    if (isUser) {
      // Remove the "[Image attached]" marker from displayed text
      final displayText = text.replaceAll('\n📷 [Image attached]', '').trim();
      if (displayText.isNotEmpty) {
        children.add(
          Text(displayText, style: const TextStyle(color: Colors.white)),
        );
      }
      if (children.isEmpty) {
        return const Text(
          '📷 Bill image',
          style: TextStyle(color: Colors.white),
        );
      }
      if (children.length == 1) return children.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    // AI message parsing (charts, tables, text, actions)
    final lines = text.split('\n');
    bool insideChartBlock = false;
    bool insideActionBlock = false;
    StringBuffer textBuffer = StringBuffer();
    StringBuffer jsonBuffer = StringBuffer();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

       if (line.trim().startsWith('```chart')) {
         if (textBuffer.isNotEmpty) {
           children.add(
             Text(
               textBuffer.toString().trim(),
               style: TextStyle(color: AppTheme.textDark),
             ),
           );
           textBuffer.clear();
         }
         insideChartBlock = true;
         continue;
       }

       if (line.trim().startsWith('```action')) {
         if (textBuffer.isNotEmpty) {
           children.add(
             Text(
               textBuffer.toString().trim(),
               style: TextStyle(color: AppTheme.textDark),
             ),
           );
           textBuffer.clear();
         }
         insideActionBlock = true;
         continue;
       }

      if ((insideChartBlock || insideActionBlock) &&
          line.trim().startsWith('```')) {
        if (insideChartBlock) {
          children.add(AiChartWidget(jsonString: jsonBuffer.toString()));
        } else if (insideActionBlock) {
          children.add(_AiActionWidget(jsonString: jsonBuffer.toString()));
        }
        jsonBuffer.clear();
        insideChartBlock = false;
        insideActionBlock = false;
        continue;
      }

      if (insideChartBlock || insideActionBlock) {
        jsonBuffer.writeln(line);
      } else {
        textBuffer.writeln(line);
      }
    }

    if (textBuffer.isNotEmpty) {
      children.add(
        Text(
          textBuffer.toString().trim(),
          style: TextStyle(color: AppTheme.textDark),
        ),
      );
    }

    if (jsonBuffer.isNotEmpty && insideChartBlock) {
      children.add(AiChartWidget(jsonString: jsonBuffer.toString()));
    }
    if (jsonBuffer.isNotEmpty && insideActionBlock) {
      children.add(_AiActionWidget(jsonString: jsonBuffer.toString()));
    }

    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Widget to display and execute AI-generated warehouse modification actions
class _AiActionWidget extends StatefulWidget {
  final String jsonString;
  const _AiActionWidget({required this.jsonString});

  @override
  State<_AiActionWidget> createState() => _AiActionWidgetState();
}

class _AiActionWidgetState extends State<_AiActionWidget> {
  bool _applied = false;
  bool _applying = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? parsed;
    try {
      parsed = json.decode(widget.jsonString);
    } catch (_) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '⚠️ Invalid action format',
          style: TextStyle(color: AppTheme.danger),
        ),
      );
    }

    final actionType = parsed?['type'] as String? ?? 'update_medicine';
    final updates = (parsed?['updates'] as List<dynamic>?) ?? [];
    final medicineData = parsed?['medicine'] as Map<String, dynamic>?;

    String title = '📦 Warehouse Update';
    IconData icon = Icons.warehouse;

    if (actionType == 'add_medicine') {
      title = '➕ Add Medicine';
      icon = Icons.add_circle;
    } else if (actionType == 'remove_medicine') {
      title = '🗑️ Remove Medicine';
      icon = Icons.delete;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _applied
            ? AppTheme.success.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _applied
              ? AppTheme.success.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _applied ? Icons.check_circle : icon,
                color: _applied ? AppTheme.success : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _applied ? '✅ Changes Applied' : title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _applied ? AppTheme.success : Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (actionType == 'update_medicine')
            ...updates.map((u) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${u['name']}: ${u['field']} → ${u['value']}',
                  style: const TextStyle(fontSize: 13),
                ),
              );
            }),
          if (actionType == 'add_medicine' && medicineData != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• New Medicine: ${medicineData['name']} (${medicineData['category']})',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (actionType == 'remove_medicine' && medicineData != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• Delete: ${medicineData['name']}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '❌ $_error',
                style: const TextStyle(color: AppTheme.danger, fontSize: 12),
              ),
            ),
          if (!_applied)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _applying
                        ? null
                        : () => _applyActions(actionType, updates, medicineData),
                    icon: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_applying ? 'Applying...' : 'Apply Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _applyActions(String actionType, List<dynamic> updates, Map<String, dynamic>? medicineData) async {
    setState(() {
      _applying = true;
      _error = null;
    });

    final hub = context.read<HubProvider>();
    bool success = false;

    if (actionType == 'add_medicine' && medicineData != null) {
      final newMedicine = Medicine(
        id: 0, // Backend will assign ID
        name: medicineData['name'] ?? '',
        category: medicineData['category'] ?? 'General',
        unit: medicineData['unit'] ?? 'Pcs',
        barcode: medicineData['barcode'] ?? '',
        purchasePrice: (medicineData['purchasePrice'] as num?)?.toDouble() ?? 0.0,
        sellingPrice: (medicineData['sellingPrice'] as num?)?.toDouble() ?? 0.0,
        mainStock: medicineData['mainStock'] ?? 0,
        storeStock: medicineData['storeStock'] ?? 0,
        lowStockThreshold: medicineData['lowStockThreshold'] ?? 10,
      );
      success = await hub.service.addMedicine(newMedicine);
    } else if (actionType == 'remove_medicine' && medicineData != null) {
      final name = medicineData['name'] as String?;
      if (name != null) {
        // Find medicine by name (fuzzy match) to get ID
        // First try exact match
        final medExact = hub.medicines
            .where((m) => m.name.toLowerCase() == name.toLowerCase())
            .firstOrNull;
        
        // If no exact match, try contains match
        final med = medExact ?? hub.medicines
            .where((m) => m.name.toLowerCase().contains(name.toLowerCase()))
            .firstOrNull;
        
        if (med != null) {
          // Show confirmation before removing
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirm Removal'),
              content: Text('Are you sure you want to remove "${med.name}" from the catalog?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                  ),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ) ?? false;
          
          if (confirmed) {
            success = await hub.service.removeMedicine(med.id);
          } else {
            setState(() {
              _error = 'Removal cancelled by user';
              _applied = false;
            });
            return;
          }
        } else {
          setState(() => _error = 'Medicine "$name" not found in catalog.');
        }
      }
    } else if (actionType == 'update_medicine') {
      int successCount = 0;
      for (final u in updates) {
        final name = u['name'] as String;
        final field = u['field'] as String;
        final value = u['value'];

        // Find medicine by name (fuzzy match)
        final med = hub.medicines
            .where((m) => m.name.toLowerCase() == name.toLowerCase())
            .firstOrNull ??
            hub.medicines
                .where((m) => m.name.toLowerCase().contains(name.toLowerCase()))
                .firstOrNull;

        if (med == null) {
          setState(() => _error = 'Medicine "$name" not found in catalog.');
          continue;
        }

        // Create updated medicine
        final updated = Medicine(
          id: med.id,
          name: med.name,
          category: med.category,
          unit: med.unit,
          barcode: med.barcode,
          purchasePrice: field == 'purchasePrice'
              ? (value as num).toDouble()
              : med.purchasePrice,
          sellingPrice: field == 'sellingPrice'
              ? (value as num).toDouble()
              : med.sellingPrice,
          mainStock: field == 'mainStock'
              ? (value as num).toInt()
              : med.mainStock,
          storeStock: field == 'storeStock'
              ? (value as num).toInt()
              : med.storeStock,
          lowStockThreshold: field == 'lowStockThreshold'
              ? (value as num).toInt()
              : med.lowStockThreshold,
        );

        final ok = await hub.service.updateMedicine(updated);
        if (ok) successCount++;
      }
      success = successCount == updates.length;
      if (successCount < updates.length && _error == null) {
        _error = 'Some updates failed ($successCount/${updates.length} succeeded)';
      }
    }

    if (success) {
      await hub.refreshData();
    }

    if (!mounted) return;
    setState(() {
      _applying = false;
      _applied = success;
    });
  }
}
