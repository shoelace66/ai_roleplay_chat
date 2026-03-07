# AI角色扮演聊天应用

一个基于Flutter开发的AI角色扮演聊天应用，支持创建角色和故事，与AI进行沉浸式对话。

## 功能特性

### 1. 多类型对象创建

- **角色（Contact）**：创建具有外貌、性格、背景的虚拟角色
- **故事（Story）**：创建具有风格、设定的故事世界
- **助手（Assistant）**：预留功能

### 2. 三种创建方式

- **普通模式**：通过表单逐项填写对象属性
- **JSON模式**：直接输入JSON格式定义对象
- **自然语言模式**：用自然语言描述，AI自动生成对象

### 3. 数组项编辑器

- 支持逐项添加、编辑、删除对象属性
- 使用Chip组件展示已添加的条目
- 点击Chip可编辑，点击删除图标可移除

### 4. 对话功能

- 与AI角色进行沉浸式对话
- 支持移动端和桌面端自适应布局
- 左侧栏显示对象列表，支持快速切换

### 5. 移动端优化

- 抽屉式侧边栏，点击菜单按钮呼出
- 底部输入框，支持键盘自适应
- 简洁的AppBar设计

## 项目结构

```
lib/
├── app.dart                                    # 应用根组件
├── main.dart                                   # 入口文件
├── constants/
│   ├── api_constants.dart                      # API配置常量
│   └── app_strings.dart                        # 应用字符串
└── features/
    └── chat/
        ├── data/
        │   ├── agent.dart                      # 持久化存储
        │   ├── models/
        │   │   ├── contact.dart                # 联系人/故事模型
        │   │   └── message.dart                # 消息模型
        │   └── repositories/
        │       └── chat_repository.dart        # 数据仓库
        ├── domain/
        │   ├── providers/
        │   │   └── chat_provider.dart          # 状态管理
        │   ├── services/
        │   │   ├── ai_service.dart             # AI服务
        │   │   ├── heartbeat_manager.dart      # 连接状态管理
        │   │   └── input_formatter.dart        # 输入格式化
        │   └── structured/
        │       ├── structured_input_prompt_composer.dart   # Prompt组装
        │       └── structured_output_regex_parser.dart     # 输出解析
        └── presentation/
            ├── pages/
            │   └── chat_page.dart              # 聊天页面
            └── widgets/
                ├── contact_sidebar.dart        # 侧边栏组件
                └── contact_editor_dialog.dart  # 对象创建对话框
```

## 快速开始

### 环境要求

- Flutter SDK >= 3.4.0
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

输出路径：`build/app/outputs/flutter-apk/app-release.apk`

## 使用指南

### 1. 创建对象

1. 点击AppBar上的"创建对象"按钮（👤+图标）
2. 选择对象类型：角色或故事
3. 选择创建模式：普通、JSON或自然语言
4. 填写对象信息并创建

### 2. 开始对话

1. 在左侧栏（移动端为抽屉菜单）选择对象
2. 在底部输入框输入消息
3. 点击发送按钮或按回车键

### 3. 删除对象

- **桌面端**：在侧边栏对象列表项右侧点击删除图标
- **移动端**：打开抽屉菜单，在底部点击删除按钮

### 4. API配置

1. 点击AppBar上的"API配置"按钮（🔑图标）
2. 输入DeepSeek API密钥
3. 可选：自定义系统提示词
4. 点击保存

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
  backgroundStory: List<String>, // 背景故事/概述
}
```

### Message（消息）

```dart
Message {
  id: String,
  role: MessageRole,    // user/assistant
  content: String,
  createdAt: DateTime,
}
```

## 技术特点

### 1. 状态管理

使用 `ChangeNotifier` 模式实现响应式状态管理：
- `ChatProvider` 管理全局状态
- UI层通过 `AnimatedBuilder` 监听状态变化
- 自动触发UI重建

### 2. 响应式布局

- 桌面端（宽度>=900px）：左右分栏布局
- 移动端（宽度<900px）：抽屉式侧边栏
- 自适应不同屏幕尺寸

### 3. 组件化设计

- `ContactSidebar`：可复用的侧边栏组件
- `ContactEditorDialog`：对象创建对话框
- 支持参数配置（如删除按钮显示位置）

### 4. 持久化存储

使用 `SharedPreferences` 存储：
- API密钥
- 系统提示词
- 联系人列表
- 各联系人消息历史

## 配置说明

### Android权限

在 `android/app/src/main/AndroidManifest.xml` 中已配置：
- `INTERNET` - 网络访问
- `ACCESS_NETWORK_STATE` - 网络状态
- `READ_EXTERNAL_STORAGE` - 读取存储
- `WRITE_EXTERNAL_STORAGE` - 写入存储

### API配置

应用使用DeepSeek API进行AI对话：
- 默认模型：`deepseek-chat`
- 支持自定义API密钥
- 支持自定义系统提示词

## 开发计划

### 已实现功能

- [x] 角色和故事创建
- [x] 三种创建模式（普通/JSON/自然语言）
- [x] 数组项编辑器
- [x] 移动端和桌面端自适应布局
- [x] 对象删除功能
- [x] API配置
- [x] 抽屉式侧边栏（移动端）

### 待实现功能

- [ ] 消息历史持久化
- [ ] 长期记忆系统
- [ ] 事件图谱
- [ ] 关键词提取
- [ ] 调试模式
- [ ] 多模态支持（图片、语音）

## 许可证

MIT License
