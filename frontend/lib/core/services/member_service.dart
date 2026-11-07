import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';
import 'api_service.dart';

class MemberService {
  static Future<String> _token() async {
    final token = await TokenStorage.getToken();

    if (token == null || token.isEmpty) {
      throw Exception('Your session has expired. Please log in again.');
    }

    return token;
  }

  static dynamic _decode(http.Response response) {
    dynamic data;

    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        throw Exception(
          'The server returned an unexpected response '
          '(${response.statusCode}).',
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    if (response.statusCode == 401) {
      throw Exception('Your session has expired. Please log in again.');
    }

    final detail = data is Map ? data['detail'] : null;

    if (detail is List) {
      throw Exception(
        detail.map((item) {
          return item is Map
              ? item['msg']?.toString() ?? 'Invalid input'
              : item.toString();
        }).join('\n'),
      );
    }

    throw Exception(
      detail?.toString() ??
          'Request failed (${response.statusCode}). Please try again.',
    );
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _token();

    final request = http.Request(
      method,
      Uri.parse('${ApiService.baseUrl}$path'),
    );

    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    });

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final client = http.Client();

    try {
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> getMembers() async {
    final data = await _request('GET', '/members/');

    if (data is! List) {
      throw Exception('Invalid member list returned by the server.');
    }

    return data
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<int> createMember({
    required String fullName,
    required String startDate,
  }) async {
    final data = await _request(
      'POST',
      '/members/',
      body: {
        'full_name': fullName,
        'start_date': startDate,
      },
    );

    return (data['member']['id'] as num).toInt();
  }

  static Future<void> updateMember({
    required int memberId,
    required String fullName,
  }) async {
    await _request(
      'PUT',
      '/members/$memberId',
      body: {'full_name': fullName},
    );
  }

  static Future<void> updateMembership({
    required int membershipId,
    required int memberId,
    required String startDate,
    required String dueDate,
  }) async {
    await _request(
      'PUT',
      '/memberships/$membershipId',
      body: {
        'member_id': memberId,
        'start_date': startDate,
        'due_date': dueDate,
      },
    );
  }

  static Future<void> renew({
    required int memberId,
    required String startDate,
  }) async {
    await _request(
      'POST',
      '/memberships/renew',
      body: {
        'member_id': memberId,
        'start_date': startDate,
      },
    );
  }

  static Future<List<Map<String, dynamic>>> history(int memberId) async {
    final data = await _request(
      'GET',
      '/memberships/member/$memberId/history',
    );

    return (data['history'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  static Future<void> deleteMember(int memberId) async {
    await _request('DELETE', '/members/$memberId');
  }

  static Future<Uint8List?> photo(int memberId) async {
    final token = await _token();

    final response = await http.get(
      Uri.parse('${ApiService.baseUrl}/members/$memberId/photo'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 200) {
      return response.bodyBytes;
    }

    _decode(response);
    return null;
  }

  static Future<void> uploadPhoto({
    required int memberId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final token = await _token();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/members/$memberId/photo'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ),
    );

    final client = http.Client();

    try {
      final streamed = await client.send(request);
      _decode(await http.Response.fromStream(streamed));
    } finally {
      client.close();
    }
  }

  static Future<void> removePhoto(int memberId) async {
    await _request('DELETE', '/members/$memberId/photo');
  }
}