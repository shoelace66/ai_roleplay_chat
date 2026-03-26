import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/utils/vector_memory_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置系统UI样式，确保安卓平台导航栏按钮显示完整
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // 设置首选方向
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 初始化 Hive 数据库
  await _initHive();

  runApp(const ChatApp());
}

/// 初始化 Hive 数据库
/// 
/// 在安卓端使用应用专用目录存储数据，确保数据持久化
Future<void> _initHive() async {
  try {
    if (Platform.isAndroid) {
      // 安卓端：使用应用专用目录，确保数据不会被系统清理
      final appDir = await getApplicationDocumentsDirectory();
      final hiveDir = Directory('${appDir.path}/hive_data');
      if (!await hiveDir.exists()) {
        await hiveDir.create(recursive: true);
      }
      Hive.init(hiveDir.path);
    } else {
      // 其他平台使用默认的 initFlutter
      await Hive.initFlutter();
    }

    // 注册 Hive 适配器
    Hive.registerAdapter(VectorEntryAdapter());
  } catch (e) {
    // 如果初始化失败，使用默认方式
    await Hive.initFlutter();
    Hive.registerAdapter(VectorEntryAdapter());
  }
}
