/// QR 数据流传输模式。
enum QrTransferMode {
  /// 顺序分片：按块循环发送，接收端需要收齐每个块。
  sequential,

  /// 喷泉码（LT码）：按 LT 编码连续发送任意冗余包，对丢帧更稳健。
  fountain,

  /// RaptorQ（系统喷泉码）：先发原始块，再发修复符号，
  /// 开销更小，约 k 个包即可解码，是喷泉码的改进版。
  raptorQ,
}

extension QrTransferModeX on QrTransferMode {
  String get label {
    switch (this) {
      case QrTransferMode.sequential:
        return '普通分片';
      case QrTransferMode.fountain:
        return '喷泉码';
      case QrTransferMode.raptorQ:
        return 'RaptorQ';
    }
  }

  String get description {
    switch (this) {
      case QrTransferMode.sequential:
        return '逐块循环发送，逻辑直观，但丢任一块都要继续等待。';
      case QrTransferMode.fountain:
        return '更适合摄像头丢帧场景，通常能更快完成接收。';
      case QrTransferMode.raptorQ:
        return '系统喷泉码：先传原始块可立即开始解码，修复块补充丢失数据，开销最小。';
    }
  }
}
