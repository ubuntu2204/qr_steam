/// QR 数据流传输模式。
enum QrTransferMode {
  /// 顺序分片：按块循环发送，接收端需要收齐每个块。
  sequential,

  /// 喷泉码：按 LT 编码连续发送任意冗余包，对丢帧更稳健。
  fountain,
}

extension QrTransferModeX on QrTransferMode {
  String get label {
    switch (this) {
      case QrTransferMode.sequential:
        return '普通分片';
      case QrTransferMode.fountain:
        return '喷泉码';
    }
  }

  String get description {
    switch (this) {
      case QrTransferMode.sequential:
        return '逐块循环发送，逻辑直观，但丢任一块都要继续等待。';
      case QrTransferMode.fountain:
        return '更适合摄像头丢帧场景，通常能更快完成接收。';
    }
  }
}
