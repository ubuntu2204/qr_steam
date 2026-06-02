import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart' as avif;
import 'package:qr_steam/qr_steam.dart';

// permission_handler 在 Web 上不可用，条件导入
import '../services/permission_service.dart';

/// Android 接收端页面：
/// 1. 请求摄像头权限。
/// 2. 使用 [QrStreamReceiver] 扫描动态 QR 码流。
/// 3. 使用普通分片或喷泉码重建压缩字节。
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
  QrTransferMode _mode = QrTransferMode.fountain;

  // 计时统计
  DateTime? _startTime;
  Duration? _elapsedTime;

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
    final granted = await CameraPermissionService.requestCameraPermission();
    if (!mounted) return;

    if (granted) {
      setState(() => _state = _ReceiverState.scanning);
    } else {
      setState(() => _state = _ReceiverState.permissionDenied);
    }
  }

  // ---------------------------------------------------------------------------
  // 解码回调
  // ---------------------------------------------------------------------------

  /// 解码完成回调：保存图片字节、记录耗时。
  void _onDecoded(Uint8List data) {
    final now = DateTime.now();
    setState(() {
      _imageBytes = data;
      _state = _ReceiverState.done;
      if (_startTime != null) {
        _elapsedTime = now.difference(_startTime!);
      }
    });
  }

  /// 进度回调：更新解码进度条和帧计数，记录第一帧时间。
  void _onProgress(double progress, int received) {
    if (received == 1 && _startTime == null) {
      _startTime = DateTime.now();
    }
    setState(() {
      _progress = progress;
      _packetsReceived = received;
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
      _state = _ReceiverState.scanning;
      _startTime = null;
      _elapsedTime = null;
    });
    _receiverKey.currentState?.reset();
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
      body: Column(
        children: [
          _ModeSelector(
            mode: _mode,
            onChanged: (newMode) {
              if (_mode == newMode) return;
              setState(() => _mode = newMode);
              if (_state == _ReceiverState.scanning ||
                  _state == _ReceiverState.done) {
                _reset();
              }
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
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
              if (!kIsWeb)
                ElevatedButton(
                  onPressed: CameraPermissionService.openSettings,
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
                    ? '请将摄像头对准发送端的 QR 码（${_mode.label}）'
                    : '${_mode.label}：已接收 $_packetsReceived 帧  '
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
                mode: _mode,
                overlay: const _ScanOverlay(),
              ),
            ),
          ],
        );

      case _ReceiverState.done:
        return _buildResultView();
    }
  }

  Widget _buildResultView() {
    final elapsed = _elapsedTime;
    final elapsedStr = elapsed == null
        ? ''
        : elapsed.inSeconds >= 1
            ? '  耗时: ${elapsed.inMilliseconds / 1000.0}s'
            : '  耗时: ${elapsed.inMilliseconds}ms';

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
                  '${_mode.label}解码完成！共接收 $_packetsReceived 帧，'
                  '数据大小: ${_formatBytes(_imageBytes?.length ?? 0)}$elapsedStr',
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

/// 三选模式选择器：普通分片 / 喷泉码 / RaptorQ
class _ModeSelector extends StatelessWidget {
  final QrTransferMode mode;
  final ValueChanged<QrTransferMode> onChanged;

  const _ModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<QrTransferMode>(
              segments: const [
                ButtonSegment(
                  value: QrTransferMode.sequential,
                  label: Text('普通'),
                  icon: Icon(Icons.view_week, size: 16),
                ),
                ButtonSegment(
                  value: QrTransferMode.fountain,
                  label: Text('喷泉码'),
                  icon: Icon(Icons.water_drop, size: 16),
                ),
                ButtonSegment(
                  value: QrTransferMode.raptorQ,
                  label: Text('RaptorQ'),
                  icon: Icon(Icons.bolt, size: 16),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onChanged(s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                mode.description,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

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
    final cutout = RRect.fromRectAndRadius(rect, const Radius.circular(24));

    // Draw only the outer mask so the camera preview remains visible inside.
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(cutout);
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawPath(overlayPath, backgroundPaint);

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
