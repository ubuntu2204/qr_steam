import 'dart:typed_data';

import 'sequential_packet.dart';

/// 顺序分片解码器。
class SequentialDecoder {
  int? _totalLength;
  int? _numChunks;
  int? _chunkSize;

  List<Uint8List?> _chunks = const [];
  int _receivedCount = 0;
  bool _complete = false;

  bool get isComplete => _complete;

  int get receivedCount => _receivedCount;

  int? get totalChunks => _numChunks;

  double get progress {
    if (_numChunks == null || _numChunks == 0) return 0.0;
    return _receivedCount / _numChunks!;
  }

  Uint8List? get decodedData {
    if (!_complete) return null;

    final builder = BytesBuilder(copy: false);
    for (final chunk in _chunks) {
      builder.add(chunk!);
    }
    return builder.toBytes().sublist(0, _totalLength!);
  }

  bool addPacket(SequentialPacket packet) {
    if (_complete) return true;

    if (_numChunks == null) {
      _initialize(packet);
    } else if (!_matchesStream(packet)) {
      return false;
    }

    if (_chunks[packet.chunkIndex] == null) {
      _chunks[packet.chunkIndex] = Uint8List.fromList(packet.data);
      _receivedCount++;
      if (_receivedCount == _numChunks) {
        _complete = true;
      }
    }

    return _complete;
  }

  void reset() {
    _totalLength = null;
    _numChunks = null;
    _chunkSize = null;
    _chunks = const [];
    _receivedCount = 0;
    _complete = false;
  }

  void _initialize(SequentialPacket packet) {
    _totalLength = packet.totalLength;
    _numChunks = packet.numChunks;
    _chunkSize = packet.chunkSize;
    _chunks = List<Uint8List?>.filled(packet.numChunks, null);
  }

  bool _matchesStream(SequentialPacket packet) =>
      packet.totalLength == _totalLength &&
      packet.numChunks == _numChunks &&
      packet.chunkSize == _chunkSize;
}
