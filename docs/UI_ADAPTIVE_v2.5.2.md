# v2.5.2 · 柔和配色与手机布局

统一主题使用低饱和灰蓝色。浅色背景接近雾白，深色背景采用柔和炭灰；按钮、选择标签与用户气泡使用较淡的容器色，减少大面积强色块。局部玻璃保留轻微模糊与透明度，减弱边缘高光和背景渐变。

创建窗口原先设有 520×460 的最小尺寸，底部两个创建方式按钮又固定排在同一行，窄屏时长标签会被挤出。现在窗口宽高受实际可用区域约束，创建方式提前到表单顶部，以可换行选项呈现。表单单独滚动，操作按钮留在窗口底部；键盘占用空间时窗口同步收缩。

聊天标题栏适应放大字体，输入框根据剩余屏幕高度调整可见行数。原有的模型切换菜单、API 入口、资料编辑与照片头像功能保留。

## Flutter 实际渲染预览

- [浅色聊天](../reports/ui-v2.5.2/chat-light.png)
- [深色聊天](../reports/ui-v2.5.2/chat-dark.png)
- [资料页](../reports/ui-v2.5.2/profile-light.png)
- [侧栏](../reports/ui-v2.5.2/sidebar-light.png)
- [320×568 创建窗口，1.3 倍字体](../reports/ui-v2.5.2/create-320x568.png)
- [640×360 横屏创建窗口，1.3 倍字体](../reports/ui-v2.5.2/create-640x360.png)

387 项测试通过，静态分析无问题。新增测试验证七种屏幕尺寸、三档字体大小下的长标签边界、键盘上方提交和自然语言描述保留；聊天矩阵覆盖多行输入、侧栏、资料标签及安全区域。预览采用系统中文字体；组件测试不等同于 Android 实机键盘与帧率测试。

复现：

```sh
flutter analyze --no-pub
flutter test --reporter expanded
flutter test test/widget/contact_editor_layout_test.dart test/widget/contact_profile_test.dart --dart-define=CAPTURE_UI=true
```

截图开关在 Windows 存在微软雅黑字体时加载该字体。安装包版本及校验值见 GitHub Release 附件。
