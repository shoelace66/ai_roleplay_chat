/// 单一协议来源：提示词、仓库和本地校验共用版本与字段定义。
class RoleplayProtocol {
  RoleplayProtocol._();

  static const version = 'roleplay-memory-v5';
  static const outputSchema = '''
{
  "protocolVersion": "$version",
  "reply": "面向用户的角色回复或故事正文",
  "memoryPatch": {
    "eventBrief": {"description": "承接点、本轮推进和结束状态，300字以内", "keywords": ["实体"], "theme": ["主题"]},
    "summary": {"description": "仅在要求总结时输出", "keywords": ["实体"]},
    "stateTransition": {"baseRevision": 0, "changes": [
      {"key": "用户定义项的ID", "from": "精确旧值", "to": "文本新值；空字符串表示清空"}
    ]},
    "relatedEventIds": [0],
    "knowledgeChanges": [
      {"scope": "world|self|user", "operation": "add|replace|remove", "from": "替换或删除时精确复制旧事实", "to": "新增或替换后的事实"}
    ],
    "belongingChanges": [
      {"operation": "add|mention|remove", "item": "物品名"}
    ]
  }
}
''';
}
