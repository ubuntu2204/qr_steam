import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

/// 支持的图像压缩格式。
///
/// - [avif]  使用 `flutter_avif` 编码，跨平台支持（Windows / Android / iOS 等）。
/// - [heic]  使用 `flutter_image_compress` 编码，仅支持 Android (API ≥ 28) /
///           iOS / macOS；Windows 上自动回退到 AVIF。
enum ImageFormat {
  avif,
  heic;

  String get label => switch (this) {
        ImageFormat.avif => 'AVIF',
        ImageFormat.heic => 'HEIC',
      };
}

/// 平台感知的截图服务。
class ScreenshotService {
  /// 捕获主屏幕并返回 PNG 字节。
  ///
  /// 仅支持桌面平台（Windows / macOS / Linux）。
  static Future<Uint8List> captureScreen() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError('captureScreen is only supported on desktop');
    }

    final tempDir = await getTemporaryDirectory();
    final path = '${tempDir.path}/qr_steam_capture.png';

    final result = await screenCapturer.capture(
      mode: CaptureMode.screen,
      imagePath: path,
      silent: true,
    );

    if (result == null) throw StateError('Screen capture returned null');

    final file = File(path);
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }
}

/// 图像压缩工具，支持 AVIF 和 HEIC 两种格式。
class ImageCompressService {
  /// 判断当前平台是否原生支持 HEIC 编码。
  static bool get heicSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// 压缩 [rawImageBytes]（PNG / JPEG / 任意可解码格式）并返回压缩后字节。
  ///
  /// - [format]       目标格式，默认 [ImageFormat.avif]。
  ///                  Windows 平台选择 HEIC 时自动回退到 AVIF。
  /// - [quality]      压缩质量 1–100，默认 55。
  /// - [maxDimension] 将最长边限制到此像素数（0 = 不缩放），默认 1280。
  static Future<Uint8List> compress(
    Uint8List rawImageBytes, {
    ImageFormat format = ImageFormat.avif,
    int quality = 55,
    int maxDimension = 1280,
  }) async {
    final resized =
        maxDimension > 0 ? _resize(rawImageBytes, maxDimension) : rawImageBytes;

    // Windows 不支持 HEIC 编码 → 静默回退到 AVIF
    final effectiveFormat = (format == ImageFormat.heic && !heicSupported)
        ? ImageFormat.avif
        : format;

    switch (effectiveFormat) {
      case ImageFormat.avif:
        return _encodeAvif(resized, quality);
      case ImageFormat.heic:
        return _encodeHeic(resized, quality);
    }
  }

  // ---------------------------------------------------------------------------
  // 私有编码方法
  // ---------------------------------------------------------------------------

  /// 使用 `flutter_avif` 编码为 AVIF（全平台支持）。
  static Future<Uint8List> _encodeAvif(Uint8List bytes, int quality) async {
    final q = _qualityToQuantizer(quality);
    return avif.encodeAvif(
      bytes,
      maxQuantizer: (q + 5).clamp(0, 63),
      minQuantizer: (q - 5).clamp(0, 63),
      speed: 6, // 1=最高质量/最慢, 10=最快/较低质量
      keepExif: false,
    );
  }

  /// 使用 `flutter_image_compress` 编码为 HEIC（Android / iOS / macOS）。
  static Future<Uint8List> _encodeHeic(Uint8List bytes, int quality) async {
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      quality: quality,
      format: CompressFormat.heic,
      keepExif: false,
    );
    return result;
  }

  // ---------------------------------------------------------------------------
  // 辅助方法
  // ---------------------------------------------------------------------------

  /// 将质量值（1–100，越高越好）转换为 AVIF 量化器（0–63，越低越好）。
  static int _qualityToQuantizer(int quality) {
    return ((100 - quality.clamp(1, 100)) * 63 / 99).round();
  }

  /// 将 [bytes] 缩放至最长边不超过 [maxSide] 像素。
  static Uint8List _resize(Uint8List bytes, int maxSide) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final w = decoded.width;
    final h = decoded.height;
    if (w <= maxSide && h <= maxSide) return bytes;

    final scale = maxSide / (w > h ? w : h);
    final resized = img.copyResize(
      decoded,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodePng(resized));
  }
}
