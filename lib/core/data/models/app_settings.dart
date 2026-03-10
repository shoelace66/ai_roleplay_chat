/// 应用设置数据模型
///
/// 存储各种限长参数，包括：
/// - 输入到 LLM 的长度限制
/// - 本地存储的长度限制
/// - 关联检索的深度和长度
class AppSettings {
  const AppSettings({
    this.maxPromptListItems = 5,
    this.maxPromptLineLength = 200,
    this.maxEdgeLines = 20,
    this.maxShortTermEvents = 10,
    this.maxLongTermEvents = 5,
    this.maxUltraTermEvents = 2,
    this.maxRelatedEvents = 5,
    this.summaryThreshold = 10,
    this.maxShortQueue = 2000,
    this.maxLongQueue = 500,
    this.maxUltraQueue = 200,
    this.searchDepth = 2,
  });

  /// Prompt 中列表项的最大数量
  final int maxPromptListItems;

  /// Prompt 中单行的最大长度
  final int maxPromptLineLength;

  /// Prompt 中边关系的最大行数
  final int maxEdgeLines;

  /// 输入 LLM 的短期事件数量
  final int maxShortTermEvents;

  /// 输入 LLM 的长期事件数量
  final int maxLongTermEvents;

  /// 输入 LLM 的超长期事件数量
  final int maxUltraTermEvents;

  /// 关联检索返回的最大事件数
  final int maxRelatedEvents;

  /// 事件总结阈值
  final int summaryThreshold;

  /// 短期队列最大容量（本地存储）
  final int maxShortQueue;

  /// 长期队列最大容量（本地存储）
  final int maxLongQueue;

  /// 超长期队列最大容量（本地存储）
  final int maxUltraQueue;

  /// 关联检索深度（邻居层级）
  final int searchDepth;

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      maxPromptListItems: (json['maxPromptListItems'] as num?)?.toInt() ?? 5,
      maxPromptLineLength: (json['maxPromptLineLength'] as num?)?.toInt() ?? 200,
      maxEdgeLines: (json['maxEdgeLines'] as num?)?.toInt() ?? 20,
      maxShortTermEvents: (json['maxShortTermEvents'] as num?)?.toInt() ?? 10,
      maxLongTermEvents: (json['maxLongTermEvents'] as num?)?.toInt() ?? 5,
      maxUltraTermEvents: (json['maxUltraTermEvents'] as num?)?.toInt() ?? 2,
      maxRelatedEvents: (json['maxRelatedEvents'] as num?)?.toInt() ?? 5,
      summaryThreshold: (json['summaryThreshold'] as num?)?.toInt() ?? 10,
      maxShortQueue: (json['maxShortQueue'] as num?)?.toInt() ?? 2000,
      maxLongQueue: (json['maxLongQueue'] as num?)?.toInt() ?? 500,
      maxUltraQueue: (json['maxUltraQueue'] as num?)?.toInt() ?? 200,
      searchDepth: (json['searchDepth'] as num?)?.toInt() ?? 2,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxPromptListItems': maxPromptListItems,
      'maxPromptLineLength': maxPromptLineLength,
      'maxEdgeLines': maxEdgeLines,
      'maxShortTermEvents': maxShortTermEvents,
      'maxLongTermEvents': maxLongTermEvents,
      'maxUltraTermEvents': maxUltraTermEvents,
      'maxRelatedEvents': maxRelatedEvents,
      'summaryThreshold': summaryThreshold,
      'maxShortQueue': maxShortQueue,
      'maxLongQueue': maxLongQueue,
      'maxUltraQueue': maxUltraQueue,
      'searchDepth': searchDepth,
    };
  }

  AppSettings copyWith({
    int? maxPromptListItems,
    int? maxPromptLineLength,
    int? maxEdgeLines,
    int? maxShortTermEvents,
    int? maxLongTermEvents,
    int? maxUltraTermEvents,
    int? maxRelatedEvents,
    int? summaryThreshold,
    int? maxShortQueue,
    int? maxLongQueue,
    int? maxUltraQueue,
    int? searchDepth,
  }) {
    return AppSettings(
      maxPromptListItems: maxPromptListItems ?? this.maxPromptListItems,
      maxPromptLineLength: maxPromptLineLength ?? this.maxPromptLineLength,
      maxEdgeLines: maxEdgeLines ?? this.maxEdgeLines,
      maxShortTermEvents: maxShortTermEvents ?? this.maxShortTermEvents,
      maxLongTermEvents: maxLongTermEvents ?? this.maxLongTermEvents,
      maxUltraTermEvents: maxUltraTermEvents ?? this.maxUltraTermEvents,
      maxRelatedEvents: maxRelatedEvents ?? this.maxRelatedEvents,
      summaryThreshold: summaryThreshold ?? this.summaryThreshold,
      maxShortQueue: maxShortQueue ?? this.maxShortQueue,
      maxLongQueue: maxLongQueue ?? this.maxLongQueue,
      maxUltraQueue: maxUltraQueue ?? this.maxUltraQueue,
      searchDepth: searchDepth ?? this.searchDepth,
    );
  }
}
