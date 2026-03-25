import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/utils/vector_memory_service.dart';

void main() {
  late VectorMemoryService vectorMemoryService;

  setUp(() async {
    vectorMemoryService = VectorMemoryService();
    await vectorMemoryService.initialize();
    await vectorMemoryService.clearAll();
  });

  tearDown(() async {
    await vectorMemoryService.clearAll();
  });

  test('测试向量存储服务初始化', () async {
    expect(vectorMemoryService, isNotNull);
  });

  test('测试添加和检索记忆条目', () async {
    // 添加测试数据
    await vectorMemoryService.addMemoryEntry(
      '1',
      '我们在旧城区钟楼调查停电异常',
      'event',
    );
    await vectorMemoryService.addMemoryEntry(
      '2',
      '用户喜欢先看证据再下结论',
      'user_knowledge',
    );
    await vectorMemoryService.addMemoryEntry(
      '3',
      '我擅长记录线索',
      'self_knowledge',
    );

    // 测试检索
    final results = await vectorMemoryService.searchSimilar('调查异常', 2);
    expect(results.length, 2);
    expect(results[0].entry.content, contains('调查'));
  });

  test('测试按类型检索', () async {
    // 添加测试数据
    await vectorMemoryService.addMemoryEntry(
      '1',
      '我们在旧城区钟楼调查停电异常',
      'event',
    );
    await vectorMemoryService.addMemoryEntry(
      '2',
      '用户喜欢先看证据再下结论',
      'user_knowledge',
    );

    // 测试按类型检索
    final eventResults = await vectorMemoryService.searchSimilar('调查', 2, type: 'event');
    expect(eventResults.length, 1);
    expect(eventResults[0].entry.type, 'event');

    final userResults = await vectorMemoryService.searchSimilar('用户', 2, type: 'user_knowledge');
    expect(userResults.length, 1);
    expect(userResults[0].entry.type, 'user_knowledge');
  });

  test('测试语义相似度计算', () async {
    // 添加测试数据
    await vectorMemoryService.addMemoryEntry(
      '1',
      '我们在旧城区钟楼调查停电异常',
      'event',
    );
    await vectorMemoryService.addMemoryEntry(
      '2',
      '我们在老城区钟塔检查电力故障',
      'event',
    );
    await vectorMemoryService.addMemoryEntry(
      '3',
      '今天天气很好',
      'event',
    );

    // 测试语义相似度
    final results = await vectorMemoryService.searchSimilar('电力问题', 3);
    expect(results.length, 3);
    expect(results[0].entry.content, contains('电力'));
    expect(results[1].entry.content, contains('停电'));
    expect(results[2].entry.content, contains('天气'));
  });
}
