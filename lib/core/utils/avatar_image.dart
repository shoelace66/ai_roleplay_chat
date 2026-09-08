import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';

abstract final class AvatarImage {
  static Future<String?> pick() async {
    const types = XTypeGroup(
      label: '头像照片',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
      uniformTypeIdentifiers: [
        'public.jpeg',
        'public.png',
        'org.webmproject.webp'
      ],
    );
    final file = await openFile(acceptedTypeGroups: [types]);
    if (file == null) return null;
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('图片超过 20 MB，请选择较小的照片。');
    }
    return normalize(await file.readAsBytes());
  }

  /// Decode real image bytes, resize before storing, and keep the avatar portable
  /// across database, backup and branch snapshots without a temporary file path.
  static Future<String> normalize(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('图片为空或超过 20 MB。');
    }
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final largest = descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height;
          final scale = largest > 512 ? 512 / largest : 1.0;
          final codec = await descriptor.instantiateCodec(
            targetWidth: (descriptor.width * scale).round().clamp(1, 512),
            targetHeight: (descriptor.height * scale).round().clamp(1, 512),
          );
          try {
            final frame = await codec.getNextFrame();
            try {
              final png =
                  await frame.image.toByteData(format: ui.ImageByteFormat.png);
              if (png == null) throw const FormatException('无法读取图片像素。');
              return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}';
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      throw const FormatException('无法读取此图片，请选择完整的 JPG、PNG 或 WebP 图片。');
    }
  }

  static Uint8List? decode(String value) {
    if (!value.startsWith('data:image/')) return null;
    try {
      return UriData.parse(value).contentAsBytes();
    } catch (_) {
      return null;
    }
  }
}
