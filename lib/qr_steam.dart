/// QR Steam – Stream binary data via animated QR codes using LT fountain codes.
///
/// Usage example (sender):
/// ```dart
/// QrStreamSender(data: myBytes, fps: 8)
/// ```
///
/// Usage example (receiver):
/// ```dart
/// QrStreamReceiver(
///   onDecoded: (Uint8List bytes) { /* use bytes */ },
///   onProgress: (double p) { /* 0.0 – 1.0 */ },
/// )
/// ```
library qr_steam;

export 'src/fountain/fountain_encoder.dart';
export 'src/fountain/fountain_decoder.dart';
export 'src/fountain/fountain_packet.dart';
export 'src/fountain/soliton.dart';
export 'src/widgets/qr_stream_sender.dart';
export 'src/widgets/qr_stream_receiver.dart';
