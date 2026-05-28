import 'dart:typed_data';

import 'sequential_packet.dart';

/// 顺序分片编码器。
class SequentialEncoder {
  static const int defaultChunkSize = 300;

  final Uint8List _data;
  final int _chunkSize;
  late final List<Uint8List> _chunks;
  late final int _numChunks;

  int _nextIndex = 0;

  SequentialEncoder(this._data, {int chunkSize = defaultChunkSize})
      : _chunkSize = chunkSize {
    assert(_data.isNotEmpty, 'Data must not be empty');
    assert(chunkSize > 0 && chunkSize <= 0xFFFF, 'chunkSize must be 1..65535');

    _numChunks = (_data.length + chunkSize - 1) ~/ chunkSize;
    _chunks = List<Uint8List>.generate(_numChunks, (index) {
      final start = index * _chunkSize;
      final end = (start + _chunkSize).clamp(0, _data.length);
      return Uint8List.fromList(_data.sublist(start, end));
    });
  }

  int get numChunks => _numChunks;

  int get chunkSize => _chunkSize;

  int get dataLength => _data.length;

  SequentialPacket nextPacket() {
    final packet = SequentialPacket(
      totalLength: _data.length,
      numChunks: _numChunks,
      chunkSize: _chunkSize,
      chunkIndex: _nextIndex,
      data: _chunks[_nextIndex],
    );
    _nextIndex = (_nextIndex + 1) % _numChunks;
    return packet;
  }

  List<SequentialPacket> encodeN(int count) =>
      List.generate(count, (_) => nextPacket());
}
