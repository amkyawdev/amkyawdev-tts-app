import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../tts/models/audio_format.dart';
import '../tts/models/engine_id.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.text,
    required this.engineId,
    required this.voiceId,
    required this.createdAt,
    required this.audioPath,
    required this.durationMs,
    required this.format,
    required this.sampleRate,
    required this.charCount,
    required this.chunkCount,
  });

  final String id;
  final String text;
  final TtsEngineId engineId;
  final String voiceId;
  final DateTime createdAt;
  final String audioPath;
  final int durationMs;
  final AudioFormat format;
  final int sampleRate;
  final int charCount;
  final int chunkCount;

  Map<String, Object?> toMap() => {
    'id': id,
    'text': text,
    'engine_id': engineId.id,
    'voice_id': voiceId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'audio_path': audioPath,
    'duration_ms': durationMs,
    'format': format.extension,
    'sample_rate': sampleRate,
    'char_count': charCount,
    'chunk_count': chunkCount,
  };

  factory HistoryEntry.fromMap(Map<String, Object?> map) {
    return HistoryEntry(
      id: map['id']! as String,
      text: map['text']! as String,
      engineId:
          TtsEngineId.fromId(map['engine_id'] as String?) ?? TtsEngineId.piper,
      voiceId: map['voice_id'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num).toInt(),
      ),
      audioPath: map['audio_path'] as String? ?? '',
      durationMs: (map['duration_ms'] as num?)?.toInt() ?? 0,
      format:
          AudioFormat.fromExtension(map['format'] as String? ?? 'wav') ??
          AudioFormat.wav,
      sampleRate: (map['sample_rate'] as num?)?.toInt() ?? 0,
      charCount: (map['char_count'] as num?)?.toInt() ?? 0,
      chunkCount: (map['chunk_count'] as num?)?.toInt() ?? 1,
    );
  }
}

/// SQLite-backed transcript history. API keys and other credentials are never
/// written here.
class HistoryRepository {
  HistoryRepository({required DatabaseFactory factory, required String path})
    : _factory = factory,
      _path = path;

  static const String _databaseName = 'amkyaw_tts_studio.db';
  static const int _version = 1;

  final DatabaseFactory _factory;
  final String _path;
  Database? _db;

  static Future<HistoryRepository> openPlatform() async {
    final base = await getDatabasesPath();
    final repository = HistoryRepository(
      factory: databaseFactory,
      path: p.join(base, _databaseName),
    );
    await repository.init();
    return repository;
  }

  Future<void> init() async {
    _db ??= await _factory.openDatabase(
      _path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE history (
              id TEXT PRIMARY KEY,
              text TEXT NOT NULL,
              engine_id TEXT NOT NULL,
              voice_id TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              audio_path TEXT NOT NULL,
              duration_ms INTEGER NOT NULL,
              format TEXT NOT NULL,
              sample_rate INTEGER NOT NULL,
              char_count INTEGER NOT NULL,
              chunk_count INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_history_created_at ON history(created_at DESC)',
          );
        },
      ),
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('HistoryRepository.init() must be awaited first');
    }
    return db;
  }

  Future<void> insert(HistoryEntry entry) async {
    await _database.insert(
      'history',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HistoryEntry>> all({String? query, TtsEngineId? engine}) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      clauses.add('(text LIKE ? OR voice_id LIKE ? OR engine_id LIKE ?)');
      final like = '%${query.trim()}%';
      args.addAll([like, like, like]);
    }
    if (engine != null) {
      clauses.add('engine_id = ?');
      args.add(engine.id);
    }
    final rows = await _database.query(
      'history',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(HistoryEntry.fromMap).toList(growable: false);
  }

  Future<HistoryEntry?> findById(String id) async {
    final rows = await _database.query(
      'history',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : HistoryEntry.fromMap(rows.first);
  }

  Future<void> delete(String id) async {
    await _database.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> clear() async {
    final rows = await _database.query('history', columns: ['audio_path']);
    final paths = rows
        .map((row) => row['audio_path'] as String?)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    await _database.delete('history');
    return paths;
  }

  Future<int> count() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS c FROM history',
    );
    return (result.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
