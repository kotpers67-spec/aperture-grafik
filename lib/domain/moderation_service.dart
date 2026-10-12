import 'dart:convert';
import 'package:http/http.dart' as http;

class ModerationService {
  const ModerationService();

  static const String blockedUsersUrl =
      'https://gitlab.com/api/v4/projects/santiyastudio%2Faperture-grafik/repository/files/blocked_users.json/raw?ref=main';

  Future<bool> isUserBlocked(String userId, {http.Client? client}) async {
    final cleanId = userId.trim().toUpperCase();
    if (cleanId.isEmpty) return false;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(
            Uri.parse(blockedUsersUrl),
            headers: {'User-Agent': 'ApertureGrafik-Moderation'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = response.body.trim();
        final dynamic decoded = jsonDecode(body);
        if (decoded is List) {
          final blockedIds = decoded
              .map((e) => e.toString().trim().toUpperCase())
              .toSet();
          return blockedIds.contains(cleanId);
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
