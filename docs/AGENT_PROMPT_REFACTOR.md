# Agent 式提示词与 API Profile 配置

v2.4.0 把角色/故事正文请求按 Agent 的职责边界重新组织。目标是让模型清楚区分应用契约、用户配置、事实状态、历史消息和本轮任务，同时减少旧事实与新事实并存、流式正文迟迟不出现等问题。

## 消息与优先级

正文请求使用以下结构：

1. `system`：应用运行契约、`roleplay-memory-v5` 输出协议、用户自定义行为指令、角色/故事配置、世界书和状态定义。
2. 原生历史消息：最近 4 条有效对话分别以 `user` 或 `assistant` role 发送，不再拼进当前用户文本。
3. 当前 `user`：包含本轮运行上下文和当前输入。

应用契约明确声明优先级和数据边界。角色配置、世界书、记忆及历史消息中的文字只作为内容使用，不能改变响应协议。`fixedInput` 与 personality、appearance、personalInfo、settings、backgroundStory、narrativeRules、otherCharacteristics 同时进入角色数据，避免固定输入一旦存在就遮蔽结构化字段。世界书同时注入地点、组织、规则和时间线事件。

本轮运行上下文包含长期知识、分层事件记忆、权威连续性状态、物品与联想内容。历史摘要不能覆盖当前状态。按用户要求，本次没有增加总 Prompt token 预算或自动裁剪策略。

## v5 结构化响应

JSON 字段固定按 `protocolVersion`、`reply`、`memoryPatch` 输出。模型在组织内容时仍先确定事件摘要与状态变化，但序列化时先写 `reply`，流式解析器因此能更早显示正文。

`memoryPatch` 新增可逆记忆操作：

- `knowledgeChanges`：按 world、self、user 范围执行 `add`、`replace` 或 `remove`。`replace.from` 和 `remove.from` 必须精确匹配现有事实，本地校验失败时跳过该操作。
- `belongingChanges`：对物品执行 `add`、`mention` 或 `remove`。
- 旧版 `worldKnowledge`、`selfKnowledge`、`userKnowledge` 和 `belongings` 仍可读取，已有数据不需要迁移。

## 每个 API Profile 的生成参数

API 设置页把“最大 Token”明确为“输出上限（max_tokens）”，每个正文 Profile 独立保存，`0` 表示不发送限制，界面允许设置到 131072。

每个 Profile 还有独立的“JSON 响应模式”开关。开启后，仅角色/故事的结构化请求发送 OpenAI 兼容的 `response_format: {"type":"json_object"}`；关闭时不发送该字段，以兼容不支持 `response_format` 的第三方接口。开关默认关闭。

PLAN/JUDGE 事件召回仍由协调器使用自己的小型输出限制，避免召回请求继承正文的大额度配置。

## 验证范围

自动测试覆盖 system/历史/current user 的消息顺序、Profile 参数持久化、JSON 模式开关、固定输入与结构化字段共存、世界书时间线、v5 流式正文提前显示，以及知识和物品的新增、替换、删除。真实供应商是否严格遵循协议仍取决于模型与兼容层实现。

### 本地验收（2026-09-08）

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --reporter expanded`：354 项全部通过。
- `git diff --check`：通过。
- `flutter build apk --release --no-pub`：构建 2.4.0+9 release APK，交付文件与构建输出 SHA-256 一致。

历史验收包 `ai-roleplay-chat-v2.4.0-agent-prompt.apk` 已清理：[下载当前版本](https://github.com/shoelace66/ai_roleplay_chat/releases/tag/v2.5.2)。

SHA-256：`b03409bdfe5ee0a91967c0ec90e7b8b6fe33793b841886db4ac8bbf02213007d`
