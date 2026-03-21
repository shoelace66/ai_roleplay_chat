import 'dart:convert';
import 'dart:math';
import 'package:hive/hive.dart';

class VectorMemoryService {
  static const String _vectorBoxName = 'vector_memory';
  static const String _embeddingModelPath = 'assets/models/embedding_model.tflite';
  
  late Box<VectorEntry> _vectorBox;
  bool _initialized = false;
  
  Future<void> initialize() async {
    if (!_initialized) {
      Hive.registerAdapter(VectorEntryAdapter());
      _vectorBox = await Hive.openBox<VectorEntry>(_vectorBoxName);
      _initialized = true;
    }
  }
  
  Future<void> addMemoryEntry(String id, String content, String type) async {
    await initialize();
    final vector = await _generateEmbedding(content);
    final entry = VectorEntry(
      id: id,
      content: content,
      type: type,
      vector: vector,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await _vectorBox.put(id, entry);
  }
  
  Future<List<VectorEntry>> searchSimilar(String query, int topK, {String? type}) async {
    await initialize();
    final queryVector = await _generateEmbedding(query);
    
    final scoredEntries = <_ScoredEntry>[];
    
    for (final entry in _vectorBox.values) {
      if (type != null && entry.type != type) continue;
      
      final similarity = _cosineSimilarity(queryVector, entry.vector);
      scoredEntries.add(_ScoredEntry(entry: entry, score: similarity));
    }
    
    scoredEntries.sort((a, b) => b.score.compareTo(a.score));
    
    return scoredEntries.take(topK).map((e) => e.entry).toList();
  }
  
  Future<void> deleteMemoryEntry(String id) async {
    await initialize();
    await _vectorBox.delete(id);
  }
  
  Future<void> clearAll() async {
    await initialize();
    await _vectorBox.clear();
  }
  
  Future<List<double>> _generateEmbedding(String text) async {
    // 这里使用简化的向量生成方法
    // 实际项目中可以使用TFLite模型或其他轻量级模型
    return _simpleEmbedding(text);
  }
  
  List<double> _simpleEmbedding(String text) {
    // 简化的文本向量化方法
    // 实际项目中应该使用更复杂的模型
    final words = text.split(RegExp(r'\s+'));
    final vector = List<double>.filled(32, 0.0);
    
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      for (int j = 0; j < word.length && j < 32; j++) {
        vector[j] += word.codeUnitAt(j) / 255.0;
      }
    }
    
    // 归一化
    final norm = sqrt(vector.fold(0.0, (sum, val) => sum + val * val));
    if (norm > 0) {
      return vector.map((v) => v / norm).toList();
    }
    return vector;
  }
  
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have the same length');
    }
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA == 0 || normB == 0) {
      return 0.0;
    }
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}

class VectorEntry {
  final String id;
  final String content;
  final String type;
  final List<double> vector;
  final int timestamp;
  
  VectorEntry({
    required this.id,
    required this.content,
    required this.type,
    required this.vector,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'type': type,
      'vector': vector,
      'timestamp': timestamp,
    };
  }
  
  factory VectorEntry.fromJson(Map<String, dynamic> json) {
    return VectorEntry(
      id: json['id'] as String,
      content: json['content'] as String,
      type: json['type'] as String,
      vector: (json['vector'] as List).map((e) => e as double).toList(),
      timestamp: json['timestamp'] as int,
    );
  }
}

class VectorEntryAdapter extends TypeAdapter<VectorEntry> {
  @override
  final typeId = 0;
  
  @override
  VectorEntry read(BinaryReader reader) {
    final id = reader.readString();
    final content = reader.readString();
    final type = reader.readString();
    final vectorLength = reader.readInt();
    final vector = List<double>.generate(vectorLength, (_) => reader.readDouble());
    final timestamp = reader.readInt();
    
    return VectorEntry(
      id: id,
      content: content,
      type: type,
      vector: vector,
      timestamp: timestamp,
    );
  }
  
  @override
  void write(BinaryWriter writer, VectorEntry obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.content);
    writer.writeString(obj.type);
    writer.writeInt(obj.vector.length);
    for (final value in obj.vector) {
      writer.writeDouble(value);
    }
    writer.writeInt(obj.timestamp);
  }
}

class _ScoredEntry {
  final VectorEntry entry;
  final double score;
  
  _ScoredEntry({required this.entry, required this.score});
}
