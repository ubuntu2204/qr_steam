import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../fountain/fountain_encoder.dart';
import '../sequential/sequential_encoder.dart';
import '../transfer/qr_transfer_mode.dart';

/// 将 [data] 以动态 QR 码流方式持续播放的组件。
/// 每一帧编码一个喷泉码包，接收方无需全部扫描、不需按顺序接收。
///
/// ```dart
/// QrStreamSender(
///   data: compressedImageBytes,
///   fps: 8,
///   size: 350,
/// )
/// ```
class QrStreamSender extends StatefulWidget {
  /// 要流式传输的原始字节数据
  final Uint8List data;

  /// 帧率（QR 码刷新频率），默认 5 fps
  final int fps;

  /// QR 码组件的渲染尺寸（逻辑像素），默认 320
  final double size;

  /// 源块大小（字节）。越小 → 块数越多但单帧 QR 越小、越易扫描。默认 300
  final int chunkSize;

  /// 传输模式。默认为喷泉码。
  final QrTransferMode mode;

  /// QR 码纠错级别，默认 M（15% 恢复能力）
  final int errorCorrectionLevel;

  const QrStreamSender({
    super.key,
    required this.data,
    this.fps = 5,
    this.size = 320,
    this.chunkSize = FountainEncoder.defaultChunkSize,
    this.mode = QrTransferMode.fountain,
    this.errorCorrectionLevel = QrErrorCorrectLevel.M,
  });

  @override
  State<QrStreamSender> createState() => _QrStreamSenderState();
}

class _QrStreamSenderState extends State<QrStreamSender> {
  late FountainEncoder _fountainEncoder; // 喷泉码编码器
  late SequentialEncoder _sequentialEncoder; // 顺序分片编码器
  Timer? _timer; // 定时器，按 fps 刷新 QR
  String _currentQrData = ''; // 当前帧的 base64url 载荷
  int _frameIndex = 0; // 已播放帧数（展示用）
  int _currentChunkIndex = 0; // 顺序模式下当前块序号（1-based）
  int _currentFountainSeqNo = 0; // 喷泉模式下当前包序号

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(QrStreamSender oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.fps != widget.fps ||
        oldWidget.chunkSize != widget.chunkSize ||
        oldWidget.mode != widget.mode) {
      _timer?.cancel();
      _reset();
    }
  }

  void _reset() {
    _fountainEncoder =
        FountainEncoder(widget.data, chunkSize: widget.chunkSize);
    _sequentialEncoder = SequentialEncoder(
      widget.data,
      chunkSize: widget.chunkSize,
    );
    _frameIndex = 0;
    _currentChunkIndex = 0;
    _currentFountainSeqNo = 0;
    _advance(); // 立即生成第一帧
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / widget.fps).round()),
      (_) => _advance(), // 每隔 1/fps 秒推进一帧
    );
  }

  /// 推进到下一帧：生成一个喷泉码包并更新组件。
  void _advance() {
    late final String qrData;
    late final int currentChunkIndex;
    late final int currentFountainSeqNo;

    switch (widget.mode) {
      case QrTransferMode.fountain:
        final packet = _fountainEncoder.nextPacket();
        qrData = packet.toBase64Url();
        currentChunkIndex = 0;
        currentFountainSeqNo = packet.seqNo;
      case QrTransferMode.sequential:
        final packet = _sequentialEncoder.nextPacket();
        qrData = packet.toBase64Url();
        currentChunkIndex = packet.chunkIndex + 1;
        currentFountainSeqNo = 0;
    }

    if (mounted) {
      setState(() {
        _currentQrData = qrData;
        _frameIndex++;
        _currentChunkIndex = currentChunkIndex;
        _currentFountainSeqNo = currentFountainSeqNo;
      });
    }
  }

  int get _numChunks {
    switch (widget.mode) {
      case QrTransferMode.fountain:
        return _fountainEncoder.numChunks;
      case QrTransferMode.sequential:
        return _sequentialEncoder.numChunks;
    }
  }

  String get _footerText {
    switch (widget.mode) {
      case QrTransferMode.fountain:
        return '喷泉包 #$_currentFountainSeqNo  •  随机冗余  •  '
            '$_numChunks chunks  •  ${widget.fps} fps';
      case QrTransferMode.sequential:
        return '顺序帧 #$_frameIndex  •  ${widget.mode.label}  •  '
            '块 $_currentChunkIndex/$_numChunks  •  ${widget.fps} fps';
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          // RepaintBoundary 隔离重绘区域，避免帧率高时干扰父组件
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: _currentQrData.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : QrImageView(
                    data: _currentQrData,
                    version: QrVersions.auto, // 自动选择 QR 版本
                    errorCorrectionLevel: widget.errorCorrectionLevel,
                    gapless: true, // 模块无间隙，提高扫描率
                    backgroundColor: Colors.white,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _footerText,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
