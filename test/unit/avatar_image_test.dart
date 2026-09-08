import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/utils/avatar_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('真实 JPG 解码缩小，保存后重新解码保持比例且不依赖文件路径', () async {
    final jpg = await File('test/fixtures/avatar-landscape.jpg').readAsBytes();
    expect(jpg.take(2), [255, 216]);
    final stored = await AvatarImage.normalize(jpg);
    expect(stored, startsWith('data:image/png;base64,'));
    final bytes = AvatarImage.decode(stored)!;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    expect(frame.image.height, 256);
    frame.image.dispose();
    codec.dispose();
  });

  test('损坏图片、空文件给出可读错误', () async {
    await expectLater(AvatarImage.normalize(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
    await expectLater(
        AvatarImage.normalize(Uint8List(0)), throwsFormatException);
    expect(AvatarImage.decode('🌿'), isNull);
    expect(AvatarImage.decode('data:image/png;base64,broken!'), isNull);
  });
}
