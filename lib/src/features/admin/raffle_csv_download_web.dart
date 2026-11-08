import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void downloadRaffleCsv(Uint8List bytes, String fileName,
    {String mimeType = 'text/csv;charset=utf-8'}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  Future<void>.delayed(const Duration(seconds: 1), () {
    web.URL.revokeObjectURL(url);
  });
}
