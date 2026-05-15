import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_steam/qr_steam.dart';

/// Android 接收端页面：
/// 1. 请求摄像头权限。
/// 2. 使用 [QrStreamReceiver] 扫描动态 QR 码流。
/// 3. 喷泉码解码器重建并合压缩字节。
/// 4. 自动识别 AVIF / HEIC 并使用对应解码器显示图片。
class ReceiverPage extends StatefulWidget {
  const ReceiverPage({super.key});

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  /// 用于调用 QrStreamReceiver 的公共 API（如 reset）
  final GlobalKey<QrStreamReceiverState> _receiverKey = GlobalKey();

  _ReceiverState _state = _ReceiverState.requestingPermission; // 页面状态
  Uint8List? _imageBytes; // 解码完成后的图片字节
  double _progress = 0.0; // 当前解码进度 [0, 1]
  int _packetsReceived = 0; // 已接收的有效帧数

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  // ---------------------------------------------------------------------------
  // 摄像头权限
  // ---------------------------------------------------------------------------

  /// 请求摄像头权限，授权后进入扫描状态。
  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _state = _ReceiverState.scanning); // 权限已授予，开始扫描
    } else {
      setState(() => _state = _ReceiverState.permissionDenied); // 权限被拒
    }
  }

  // ---------------------------------------------------------------------------
  // 解码回调
  // ---------------------------------------------------------------------------

  /// 喷泉码解码完成回调：保存图片字节并切换到完成状态。
  void _onDecoded(Uint8List data) {
    setState(() {
      _imageBytes = data; // 全量图片字节
      _state = _ReceiverState.done; // 状态转为“已完成”
    });
  }

  /// 进度回调：更新解码进度条和帧计数。
  void _onProgress(double progress, int received) {
    setState(() {
      _progress = progress; // 0.0 – 1.0
      _packetsReceived = received; // 已接收的有效包数
    });
  }

  // ---------------------------------------------------------------------------
  // 操作
  // ---------------------------------------------------------------------------

  /// 重置到初始扫描状态，同时重置喷泉码解码器。
  void _reset() {
    setState(() {
      _imageBytes = null;
      _progress = 0.0;
      _packetsReceived = 0;
      _state = _ReceiverState.scanning; // 回到扫描状态
    });
    _receiverKey.currentState?.reset(); // 通过 GlobalKey 重置部件内部解码器
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Steam – 接收端'),
        actions: [
          if (_state != _ReceiverState.requestingPermission &&
              _state != _ReceiverState.permissionDenied)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新接收',
              onPressed: _reset,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ReceiverState.requestingPermission:
        return const Center(child: CircularProgressIndicator());

      case _ReceiverState.permissionDenied:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('需要摄像头权限', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text('请在设置中授予摄像头访问权限',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: openAppSettings,
                child: const Text('打开设置'),
              ),
            ],
          ),
        );

      case _ReceiverState.scanning:
        return Column(
          children: [
            // 解码进度条（progress 为 null 时显示不确定动画）
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              minHeight: 4,
            ),
            // 状态文本：提示对准或显示已接收帧数
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _packetsReceived == 0
                    ? '请将摄像头对准发送端的 QR 码'
                    : '已接收 $_packetsReceived 帧  '
                        '${(_progress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            // 摄像头 + QR 扫描组件
            Expanded(
              child: QrStreamReceiver(
                key: _receiverKey,
                onDecoded: _onDecoded,
                onProgress: _onProgress,
                overlay: _ScanOverlay(),
              ),
            ),
          ],
        );

      case _ReceiverState.done:
        return _buildResultView();
    }
  }

  Widget _buildResultView() {
    return Column(
      children: [
        // 成功提示条
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.green.shade50,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '解码完成！共接收 $_packetsReceived 帧，'
                  '数据大小: ${_formatBytes(_imageBytes?.length ?? 0)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        // 解码后的图片区域（支持手势缩放）
        Expanded(
          child: _imageBytes == null
              ? const Center(child: Text('无图像数据'))
              : InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: _isAvif(_imageBytes!)
                      // flutter_avif 解码 AVIF，支持跨平台包括较旧 Android
                      ? avif.AvifImage.memory(
                          _imageBytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, err, __) => Center(
                            child: Text('图片解码失败: $err',
                                style: const TextStyle(color: Colors.red)),
                          ),
                        )
                      // HEIC / JPEG 等其他格式使用 Flutter 内置解码器
                      : Image.memory(
                          _imageBytes!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, err, __) => Center(
                            child: Text('图片解码失败: $err',
                                style: const TextStyle(color: Colors.red)),
                          ),
                        ),
                ),
        ),

        // 操作按鈕区域
        Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.camera_alt),
            label: const Text('再次扫描'),
          ),
        ),
      ],
    );
  }

  /// 将字节数格式化为可读字符串（B / KB / MB）。
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  /// 通过 ISOBMFF 容器魔数判断字节是否为 AVIF 格式。
  ///
  /// AVIF 文件结构：[4 字节 box 大小] + 'ftyp' + major brand ('avif'/'avis')。
  static bool _isAvif(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final ftyp = String.fromCharCodes(bytes.sublist(4, 8));
    if (ftyp != 'ftyp') return false;
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    return brand == 'avif' || brand == 'avis';
  }
}

// ---------------------------------------------------------------------------
// 辅助类型和小部件
// ---------------------------------------------------------------------------

/// 页面内部状态枚举：摄像头权限请求 / 权限拒绝 / 扫描中 / 已完成。
enum _ReceiverState { requestingPermission, permissionDenied, scanning, done }

/// 扫描区域半透明方形覆盖层。
class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _OverlayPainter(),
        child: Container(),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dim = size.shortestSide * 0.7;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: dim,
      height: dim,
    );

    // Darken everything outside the scan square
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawRect(Offset.zero & size, backgroundPaint);
    canvas.drawRect(rect, Paint()..blendMode = BlendMode.clear);

    // Corners
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const cl = 24.0; // corner length

    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      final dx = corner == rect.topLeft || corner == rect.bottomLeft ? cl : -cl;
      final dy = corner == rect.topLeft || corner == rect.topRight ? cl : -cl;
      canvas.drawLine(corner, corner.translate(dx, 0), cornerPaint);
      canvas.drawLine(corner, corner.translate(0, dy), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
