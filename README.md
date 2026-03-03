# AI角色扮演聊天应用

一个基于Flutter开发的AI角色扮演聊天应用，支持长期记忆管理、事件图谱和结构化LLM交互。

## 核心特性

### 1. 长期记忆系统

#### 三级事件队列
- **短期事件队列**：存储最近的对话事件（最多120条）
- **长期事件队列**：存储总结后的重要事件（最多60条）
- **超长期事件队列**：存储核心历史事件（最多30条）

#### 自动事件总结
- 当短期队列中未总结事件达到10条时，触发LLM自动总结
- 支持将短期事件合并为长期事件，长期事件合并为超长期事件
- 被总结的事件会标记为"已总结"，并建立与总结事件的边关系

#### 知识库管理
- **世界观知识**：角色对世界认知的存储
- **自我认知**：角色对自己的了解
- **用户认知**：角色对用户的记忆
- 每种知识保留最近5条输入LLM，超出部分本地存储

### 2. 事件图谱

#### 图结构数据模型
- **事件节点**（EventNode）：包含时间、地点、人物、起因、经过、结果、态度
- **边关系**（EventEdge）：连接相关事件，支持双向关联
- **物品节点**：与事件建立关联，支持物品相关事件检索

#### 智能事件检索
- 基于关键词匹配搜索相关事件
- 支持通过边关系扩展搜索（关联事件自动注入）
- 物品关联事件检索：搜索与物品相关的事件

### 3. 关键词提取与关联

#### 双模式关键词提取
- **本地提取**：使用正则表达式从用户输入提取关键词
- **LLM提取**：调用专用LLM进行语义关键词抽取
- **合并策略**：合并两种来源，去重后用于事件搜索

### 4. 结构化LLM交互

#### 输入Prompt组织
- 系统提示词 + 联系人信息合并
- 事件输入格式：短期10条 + 长期5条 + 超长期2条 + 关联5条
- 知识和物品按优先级排序

#### 输出格式要求
```json
{
  "reply": "AI的回复内容",
  "memoryPatch": {
    "worldKnowledge": [],
    "selfKnowledge": [],
    "userKnowledge": [],
    "events": [{"time": "", "location": "", "characters": "", "cause": "", "process": "", "result": "", "attitude": ""}],
    "belongings": [],
    "status": [],
    "mood": "",
    "time": ""
  }
}
```

### 5. 调试模式

- 显示关键词提取结果（本地/LLM/合并）
- 展示完整的系统Prompt
- 实时查看事件图谱状态

## 项目架构

```
lib/
├── constants/
│   ├── api_constants.dart          # API配置常量
│   └── app_strings.dart            # 应用字符串
├── core/
│   └── services/
│       └── dio_client.dart         # HTTP客户端配置
├── features/
│   └── chat/
│       ├── data/
│       │   ├── agent.dart          # 持久化存储（SharedPreferences）
│       │   ├── models/
│       │   │   ├── contact.dart    # 联系人模型（含事件图谱）
│       │   │   ├── message.dart    # 消息模型
│       │   │   ├── ai_request.dart # AI请求体
│       │   │   └── ai_response.dart# AI响应解析
│       │   └── repositories/
│       │       └── chat_repository.dart  # 数据仓库
│       ├── domain/
│       │   ├── providers/
│       │   │   └── chat_provider.dart    # 核心状态管理
│       │   ├── services/
│       │   │   ├── ai_service.dart       # AI服务
│       │   │   ├── heartbeat_manager.dart # 连接状态管理
│       │   │   └── input_formatter.dart  # 输入格式化
│       │   └── structured/
│       │       ├── structured_input_prompt_composer.dart  # Prompt组装
│       │       └── structured_output_regex_parser.dart    # 输出解析
│       └── presentation/
│           └── pages/
│               └── chat_page.dart  # 聊天页面
└── main.dart
```

## 核心流程

### 1. 初始化流程
```
ChatProvider.initialize()
├── 读取Agent设置（API密钥、系统提示词）
├── 读取联系人列表
├── 读取各联系人消息历史
└── 初始化心跳检测
```

### 2. 消息发送流程
```
sendMessage(rawInput)
├── 格式化输入并创建用户消息
├── 提取关键词（本地 + LLM）
├── 构建Prompt联系人（筛选事件和知识）
├── 组装系统Prompt
├── 发送AI请求
├── 解析响应提取reply
├── 更新联系人记忆（memoryPatch）
└── 触发事件总结（如达到阈值）
```

### 3. 事件总结流程
```
_promoteBySummary()
├── 检查短期队列未总结事件数 >= 10
│   └── 调用LLM总结为长期事件
│       ├── 构建总结Prompt
│       ├── 请求LLM决策（n和event）
│       ├── 创建总结事件节点
│       ├── 建立边关系（总结事件 → 被总结事件）
│       └── 标记被总结事件
└── 检查长期队列未总结事件数 >= 10
    └── 总结为超长期事件
```

### 4. 记忆闭环
```
LLM输出 memoryPatch
    ↓
更新 Contact（知识、事件、物品、状态）
    ↓
持久化到 SharedPreferences
    ↓
下一轮对话时 Contact 参与 Prompt 组装
    ↓
更新后的记忆重新进入 LLM 上下文
```

## 数据模型

### Contact（联系人）
```dart
Contact {
  id, name, avatar, category,
  personality, appearance, backgroundStory,  // 角色设定
  worldKnowledge, selfKnowledge, userKnowledge,  // 知识库
  events, eventGraph,  // 事件存储
  belongings, status, mood, time,  // 状态
  createdAt
}
```

### EventGraphMemory（事件图谱）
```dart
EventGraphMemory {
  shortTermQueue,      // 短期事件队列
  longTermQueue,       // 长期事件队列
  ultraLongTermQueue,  // 超长期事件队列
  knowledgeNodes,      // 知识节点
  belongingEventQueues,// 物品-事件关联队列
  edges,               // 边关系
  turnCount            // 对话轮数
}
```

### EventNode（事件节点）
```dart
EventNode {
  id, tier,           // 标识和层级
  event: {            // 事件内容
    time, location, characters,
    cause, process, result, attitude
  },
  createdAtMs,        // 创建时间
  summarized          // 是否已总结
}
```

## 快速开始

### 环境要求
- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android SDK / Xcode（用于移动端）
- Chrome（用于Web端）

### 安装依赖
```bash
flutter pub get
```

### 运行应用

**Android:**
```bash
flutter run -d android
```

**iOS:**
```bash
flutter run -d ios
```

**Web:**
```bash
flutter run -d chrome
```

### 构建Release版本

**Android APK:**
```bash
flutter build apk --release
```

**Android App Bundle:**
```bash
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ios --release
```

## 配置说明

### API密钥配置
1. 在应用设置页面输入DeepSeek API密钥
2. 密钥会加密存储在SharedPreferences中

### 系统提示词配置
支持自定义系统提示词，会与联系人信息自动合并。

### 调试模式
在聊天页面点击调试按钮可开启/关闭调试模式，查看：
- 关键词提取详情
- 完整Prompt内容
- 事件图谱状态

## 技术亮点

### 1. 事件图谱设计
- 使用图结构存储事件关系，支持复杂关联查询
- 三级队列实现记忆的自然衰减和总结
- 边关系支持双向遍历，便于关联事件检索

### 2. 智能Prompt组装
- 根据稳定性排序（固定内容在前，变量在后）
- 动态筛选相关事件和知识，控制Prompt长度
- 关键词驱动的关联内容注入

### 3. 容错机制
- LLM输出解析失败时自动降级
- 事件总结失败时使用强制总结策略
- 网络异常时自动重连

### 4. 性能优化
- 事件队列长度限制，防止内存溢出
- 关键词缓存，避免重复提取
- 增量持久化，减少IO操作

## 扩展建议

### 1. 消息历史持久化
当前消息历史仅内存存储，建议：
- 添加消息历史持久化
- 支持分页加载
- 实现消息搜索

### 2. 多模态支持
- 支持图片输入/输出
- 语音消息支持
- 文件附件管理

### 3. 高级记忆管理
- 记忆权重计算
- 自动记忆遗忘
- 用户手动编辑记忆

### 4. 群聊支持
- 多角色同时对话
- 角色间关系管理
- 群聊上下文维护

## 许可证

MIT License

## 贡献指南

欢迎提交Issue和Pull Request！

1. Fork本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送分支 (`git push origin feature/AmazingFeature`)
5. 创建Pull Request

---

**注意**：本项目为学习和演示用途，生产环境使用请自行评估安全性和稳定性。
