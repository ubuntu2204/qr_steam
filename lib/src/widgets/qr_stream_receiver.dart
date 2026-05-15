import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../fountain/fountain_decoder.dart';
import '../fountain/fountain_packet.dart';

/// [QrStreamReceiver] 解码完成时的回调类型
typedef OnDecodedCallback = void Function(Uint8List data);

/// [QrStreamReceiver] 进度回调类型
typedef OnProgressCallback = void Function(double progress, int received);

/// 使用设备摄像头扫描 [QrStreamSender] 发出的动态 QR 码流，
/// 并通过 LT 喷泉码解码器重建原始数据的组件。
///
/// ```dart
/// QrStreamReceiver(
///   onDecoded: (bytes) => setState(() => _image = bytes),
///   onProgress: (p, n) => print('$n 帧, ${(p*100).toInt()}%'),
/// )
/// ```
class QrStreamReceiver extends StatefulWidget {
  /// 全部数据重建完成后调用一次。
  final OnDecodedCallback onDecoded;

  /// 可选的进度回调：[progress] ∈ [0, 1]，[received] 为已接收帧数。
  final OnProgressCallback? onProgress;

  /// 叠加在摄像头预览上方的可选扫描框组件。
  final Widget? overlay;

  const QrStreamReceiver({
    super.key,
    required this.onDecoded,
    this.onProgress,
    this.overlay,
  });

  @override
  State<QrStreamReceiver> createState() => QrStreamReceiverState();
}

class QrStreamReceiverState extends State<QrStreamReceiver> {
  final FountainDecoder _decoder = FountainDecoder(); // 喷泉码解码器
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal, // 平衡扫描速度与 CPU 占用
  );

  int _received = 0; // 已成功解析的包数
  bool _done = false; // 是否已全部解码完成

  // ---------------------------------------------------------------------------
  // 公共 API（可通过 GlobalKey 访问）
  // ---------------------------------------------------------------------------

  /// 重置解码器并重启摄像头，准备接收下一流。
  void reset() {
    _decoder.reset();
    setState(() {
      _received = 0;
      _done = false;
    });
    _controller.start();
  }

  // ---------------------------------------------------------------------------
  // 私有方法
  // ---------------------------------------------------------------------------

  /// 摄像头每次扫到条形码时触发。
  void _onDetect(BarcodeCapture capture) {
    if (_done) return; // 已完成，不再处理

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      try {
        // 尝试将扫描结果解析为喷泉码包
        final pkt = FountainPacket.fromBase64Url(raw);
        final complete = _decoder.addPacket(pkt);

        setState(() => _received++);
        widget.onProgress?.call(_decoder.progress, _received);

        if (complete) {
          setState(() => _done = true);
          _controller.stop(); // 停止摄像头，节省电池
          widget.onDecoded(_decoder.decodedData!);
          return;
        }
      } catch (_) {
        // 不是有效的 QrStream 包（如普通二维码），静默忽略
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 摄像头预览 + QR 扫描器
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),

        // 扫描区域覆盖层（可选）
        if (widget.overlay != null) widget.overlay!,

        // Status bar at the bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: _done
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.greenAccent, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '解码完成！',
                          style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '已接收 $_received 帧  '
                          '${(_decoder.progress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
