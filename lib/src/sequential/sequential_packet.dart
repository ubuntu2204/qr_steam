import 'dart:convert';
import 'dart:typed_data';

/// 顺序分片数据包，可嵌入 QR 码。
///
/// 二进制线路格式（大端序，固定 17 字节头部 + 载荷）：
/// ```
/// [0..3]   magic      : 0x51534551  (ASCII: 'QSEQ')
/// [4]      version    : 0x01
/// [5..8]   totalLen   : uint32
/// [9..10]  numChunks  : uint16
/// [11..12] chunkSize  : uint16
/// [13..14] chunkIndex : uint16
/// [15..16] dataLength : uint16
/// [17..N]  data       : dataLength 字节
/// ```
class SequentialPacket {
  static const int _magic = 0x51534551;
  static const int _version = 1;

  static const int headerSize = 17;

  final int totalLength;
  final int numChunks;
  final int chunkSize;
  final int chunkIndex;
  final Uint8List data;

  const SequentialPacket({
    required this.totalLength,
    required this.numChunks,
    required this.chunkSize,
    required this.chunkIndex,
    required this.data,
  });

  Uint8List toBytes() {
    final buf = Uint8List(headerSize + data.length);
    final view = ByteData.sublistView(buf);

    view.setUint32(0, _magic);
    view.setUint8(4, _version);
    view.setUint32(5, totalLength);
    view.setUint16(9, numChunks);
    view.setUint16(11, chunkSize);
    view.setUint16(13, chunkIndex);
    view.setUint16(15, data.length);
    buf.setRange(headerSize, buf.length, data);
    return buf;
  }

  factory SequentialPacket.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw const FormatException('SequentialPacket: too short');
    }

    final view = ByteData.sublistView(bytes, 0, headerSize);
    if (view.getUint32(0) != _magic) {
      throw const FormatException('SequentialPacket: bad magic');
    }
    if (view.getUint8(4) != _version) {
      throw const FormatException('SequentialPacket: unsupported version');
    }

    final totalLength = view.getUint32(5);
    final numChunks = view.getUint16(9);
    final chunkSize = view.getUint16(11);
    final chunkIndex = view.getUint16(13);
    final dataLength = view.getUint16(15);
    final data = bytes.sublist(headerSize);

    if (data.length != dataLength) {
      throw FormatException(
        'SequentialPacket: expected $dataLength data bytes, got ${data.length}',
      );
    }
    if (chunkIndex >= numChunks) {
      throw const FormatException('SequentialPacket: chunkIndex out of range');
    }
    if (dataLength == 0 || dataLength > chunkSize) {
      throw const FormatException('SequentialPacket: invalid chunk length');
    }

    return SequentialPacket(
      totalLength: totalLength,
      numChunks: numChunks,
      chunkSize: chunkSize,
      chunkIndex: chunkIndex,
      data: Uint8List.fromList(data),
    );
  }

  String toBase64Url() => base64Url.encode(toBytes());

  factory SequentialPacket.fromBase64Url(String encoded) =>
      SequentialPacket.fromBytes(base64Url.decode(encoded));
}
