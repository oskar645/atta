import 'dart:typed_data';
import 'api_client.dart';

class TopBannersApi {
  const TopBannersApi(this.client);
  final ApiClient client;
  Future<Map<String, dynamic>> active(String lastId) async =>
      Map<String, dynamic>.from(await client.get('/top-banners/active',
              queryParameters: lastId.isEmpty ? null : {'after_id': lastId})
          as Map);
  Future<Map<String, dynamic>> list() async => Map<String, dynamic>.from(
      await client.get('/admin/top-banners', authorized: true) as Map);
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await client.post('/admin/top-banners',
          body: body, authorized: true) as Map);
  Future<Map<String, dynamic>> update(
          String id, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(await client.patch('/admin/top-banners/$id',
          body: body, authorized: true) as Map);
  Future<void> action(String id, String action,
      [Map<String, dynamic>? body]) async {
    await client.post('/admin/top-banners/$id/$action',
        body: body ?? const {}, authorized: true);
  }

  Future<void> track(String id, String event, String sessionId) async {
    await client
        .post('/top-banners/$id/$event', body: {'session_id': sessionId});
  }

  Future<void> delete(String id) async {
    await client.delete('/admin/top-banners/$id', authorized: true);
  }

  Future<Map<String, dynamic>> stats(String id) async =>
      Map<String, dynamic>.from(await client.get(
        '/admin/top-banners/$id/stats',
        authorized: true,
      ) as Map);

  Future<Map<String, dynamic>> upload(
          String id, Uint8List bytes, String name, String type) async =>
      Map<String, dynamic>.from(await client.postMultipart(
          '/media/top-banners/$id/image',
          bytes: bytes,
          fileName: name,
          contentType: type,
          authorized: true) as Map);
}
