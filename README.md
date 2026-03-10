# AI 角色扮演聊天应用

一个基于 Flutter 开发的 AI 角色扮演聊天应用，支持创建角色和故事，与 AI 进行沉浸式对话。

## 功能特性

### 1. 多类型对象创建

- **角色（Contact）**：创建具有外貌、性格、背景的虚拟角色
- **故事（Story）**：创建具有风格、设定的故事世界
- **助手（Assistant）**：预留功能

### 2. 三种创建方式

- **普通模式**：通过表单逐项填写对象属性
- **JSON 模式**：直接输入 JSON 格式定义对象
- **自然语言模式**：用自然语言描述，AI 自动生成对象

### 3. 数组项编辑器

- 支持逐项添加、编辑、删除对象属性
- 使用 Chip 组件展示已添加的条目
- 点击 Chip 可编辑，点击删除图标可移除

### 4. 对话功能

- 与 AI 角色进行沉浸式对话
- 支持移动端和桌面端自适应布局
- 左侧栏显示对象列表，支持快速切换

### 5. 长期记忆系统

- **事件图（Event Graph）**：三层级事件存储（短期/长期/超长期）
- **知识库**：世界观知识、自我认知、对用户的了解
- **物品关联**： belongings 与事件的关联
- **故事设定**： settings 与事件的关联
- **智能检索**：基于关键词的事件检索和联想

### 6. 应用设置

可配置的限长参数：

| 分类 | 参数 | 默认值 | 说明 |
|------|------|--------|------|
| **LLM 输入** | 短期事件数量 | 10 | 输入到 LLM 的短期事件数量 |
| | 长期事件数量 | 5 | 输入到 LLM 的长期事件数量 |
| | 超长期事件数量 | 2 | 输入到 LLM 的超长期事件数量 |
| | 关联事件数量 | 5 | 关键词检索返回的最大事件数 |
| **本地存储** | 短期队列容量 | 2000 | 本地存储的短期事件最大数量 |
| | 长期队列容量 | 500 | 本地存储的长期事件最大数量 |
| | 超长期队列容量 | 200 | 本地存储的超长期事件最大数量 |
| **Prompt** | 列表项数量 | 5 | Prompt 中列表项的最大数量 |
| | 单行长度 | 200 | Prompt 中单行的最大字符数 |
| | 边关系行数 | 20 | Prompt 中边关系的最大行数 |
| **事件处理** | 总结阈值 | 10 | 触发事件总结的最小事件数 |
| **关联检索** | 检索深度 | 2 | 关联检索的邻居层级深度 |

### 7. 移动端优化

- 抽屉式侧边栏，点击菜单按钮呼出
- 底部输入框，支持键盘自适应
- 简洁的 AppBar 设计

## 快速开始

### 环境要求

- Flutter SDK >= 3.4.0
- Dart SDK >= 3.0.0
- Android SDK / Xcode（用于移动端）
- Chrome（用于 Web 端）

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

### 构建 Release 版本

**Android APK:**
```bash
flutter build apk --release
```
输出路径：`build/app/outputs/flutter-apk/app-release.apk`

## 下载 APK

直接下载预编译的 APK 文件：[ai_roleplay_chat.apk](./ai_roleplay_chat.apk)

## 使用指南

### 1. 创建对象

- 点击 AppBar 上的"创建对象"按钮（👤+ 图标）
- 选择对象类型：角色或故事
- 选择创建模式：普通、JSON 或自然语言
- 填写对象信息并创建

### 2. 开始对话

- 在左侧栏（移动端为抽屉菜单）选择对象
- 在底部输入框输入消息
- 点击发送按钮或按回车键

### 3. 删除对象

- 桌面端：在侧边栏对象列表项右侧点击删除图标
- 移动端：打开抽屉菜单，在底部点击删除按钮

### 4. API 配置

- 点击 AppBar 上的"API 配置"按钮（🔑 图标）
- 输入 DeepSeek API 密钥
- 可选：自定义系统提示词
- 点击保存

### 5. 应用设置

- 点击 AppBar 上的"设置"按钮（⚙️ 图标）
- 调整各类限长参数
- 点击"保存"

## 项目结构

```
lib/
├── app.dart                                    # 应用根组件
├── main.dart                                   # 入口文件
├── constants/
│   ├── api_constants.dart                      # API 配置常量
│   └── app_strings.dart                        # 应用字符串
├── core/
│   ├── data/
│   │   └── models/
│   │       └── app_settings.dart               # 应用设置模型
│   ├── presentation/
│   │   └── pages/
│   │       └── app_settings_page.dart          # 设置页面
│   └── utils/
│       ├── structured_input_prompt_composer.dart   # Prompt 组装
│       └── structured_output_regex_parser.dart     # 输出解析
└── features/
    └── chat/
        ├── data/
        │   ├── datasources/
        │   │   └── chat_local_storage.dart       # 本地存储
        │   ├── models/
        │   │   ├── contact.dart                  # 联系人/故事模型
        │   │   └── message.dart                  # 消息模型
        │   └── repositories/
        │       └── chat_repository.dart          # 数据仓库
        ├── domain/
        │   ├── providers/
        │   │   └── chat_provider.dart            # 状态管理
        │   └── services/
        │       ├── heartbeat_manager.dart        # 连接状态管理
        │       └── input_formatter.dart          # 输入格式化
        └── presentation/
            ├── pages/
            │   └── chat_page.dart                # 聊天页面
            └── widgets/
                ├── contact_sidebar.dart          # 侧边栏组件
                └── contact_editor_dialog.dart    # 对象创建对话框
```

## 数据模型

### Contact（联系人/故事）

```dart
Contact {
  id: String,                    // 唯一标识符
  name: String,                  // 名称
  avatar: String,                // 头像（emoji）
  category: ContactCategory,     // 类型：contact/story/assistant
  personality: List<String>,     // 性格特点/风格
  appearance: List<String>,      // 外貌特征（仅角色）
  personalInfo: List<String>,    // 个人信息（仅角色）
  settings: List<Map>,           // 故事设定（仅故事）
  backgroundStory: List<String>, // 背景故事/概述
  worldKnowledge: List<String>,  // 世界观知识
  selfKnowledge: List<String>,   // 自我认知
  userKnowledge: List<String>,   // 对用户的了解
  events: List<EventMemory>,     // 事件记忆
  eventGraph: EventGraphMemory,  // 事件图
  belongings: List<String>,      // 物品持有
  status: List<String>,          // 身体状态
  mood: String,                  // 情绪状态
  time: String,                  // 当前时间
}
```

### EventMemory（事件）

```dart
EventMemory {
  time: String,        // 时间
  location: String,    // 地点
  characters: String,  // 人物
  cause: String,       // 起因
  process: String,     // 经过
  result: String,      // 结果
  attitude: String,    // 态度
}
```

### Setting（故事设定）

```dart
Setting {
  key: String,         // 设定名称
  value: String,       // 设定描述
  relate: List<String> // 关联词
}
```

## 技术特点

### 1. 状态管理

使用 ChangeNotifier 模式实现响应式状态管理：
- ChatProvider 管理全局状态
- UI 层通过 AnimatedBuilder 监听状态变化
- 自动触发 UI 重建

### 2. 响应式布局

- 桌面端（宽度 >= 900px）：左右分栏布局
- 移动端（宽度 < 900px）：抽屉式侧边栏
- 自适应不同屏幕尺寸

### 3. 组件化设计

- ContactSidebar：可复用的侧边栏组件
- ContactEditorDialog：对象创建对话框
- 支持参数配置（如删除按钮显示位置）

### 4. 持久化存储

使用 SharedPreferences 存储：
- API 密钥
- 系统提示词
- 应用设置
- 联系人列表
- 各联系人消息历史

### 5. 事件图系统

三层级事件存储：
- **短期队列**：最近事件，最多 2000 条
- **长期队列**：总结事件，最多 500 条
- **超长期队列**：历史事件，最多 200 条

智能检索：
- 关键词匹配
- 邻居事件联想
- Belonging 关联
- Setting 关联
- LRU 排序

## 配置说明

### Android 权限

在 `android/app/src/main/AndroidManifest.xml` 中已配置：

- `INTERNET` - 网络访问
- `ACCESS_NETWORK_STATE` - 网络状态
- `READ_EXTERNAL_STORAGE` - 读取存储
- `WRITE_EXTERNAL_STORAGE` - 写入存储
- `MANAGE_EXTERNAL_STORAGE` - 管理外部存储
- `FOREGROUND_SERVICE` - 前台服务
- `WAKE_LOCK` - 唤醒锁定
- `RECEIVE_BOOT_COMPLETED` - 开机启动

### API 配置

应用使用 DeepSeek API，需要在设置中配置 API Key。

## 许可证

MIT License
