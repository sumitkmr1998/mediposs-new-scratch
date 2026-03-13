import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/chat_thread.dart';
import '../models/chat_message.dart';

class ChatDbService {
  static final ChatDbService _instance = ChatDbService._();
  static ChatDbService get instance => _instance;

  ChatDbService._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mediposs_analysis_chat.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chat_threads (
        id TEXT PRIMARY KEY,
        title TEXT,
        createdAt TEXT,
        updatedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        threadId TEXT,
        role TEXT,
        content TEXT,
        imagePath TEXT,
        createdAt TEXT,
        FOREIGN KEY (threadId) REFERENCES chat_threads (id) ON DELETE CASCADE
      )
    ''');
  }

  // Thread Ops
  Future<String> createThread(String title) async {
    final db = await database;
    final thread = ChatThread(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Simple UUID
      title: title,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.insert('chat_threads', thread.toMap());
    return thread.id;
  }

  Future<List<ChatThread>> getThreads() async {
    final db = await database;
    final maps = await db.query('chat_threads', orderBy: 'updatedAt DESC');
    return maps.map((m) => ChatThread.fromMap(m)).toList();
  }

  Future<void> deleteThread(String threadId) async {
    final db = await database;
    await db.delete('chat_threads', where: 'id = ?', whereArgs: [threadId]);
  }

  Future<void> updateThreadTimestamp(String threadId) async {
    final db = await database;
    await db.update(
      'chat_threads',
      {'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [threadId],
    );
  }

  // Message Ops
  Future<void> saveMessage(ChatMessage message) async {
    final db = await database;
    await db.insert('chat_messages', message.toMap());
    await updateThreadTimestamp(message.threadId);
  }

  Future<List<ChatMessage>> getMessages(String threadId) async {
    final db = await database;
    final maps = await db.query(
      'chat_messages',
      where: 'threadId = ?',
      whereArgs: [threadId],
      orderBy: 'createdAt ASC',
    );
    return maps.map((m) => ChatMessage.fromMap(m)).toList();
  }
}
