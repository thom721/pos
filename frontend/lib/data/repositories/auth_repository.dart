import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/core/constants.dart';
import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/user_model.dart';
import 'dart:convert';

class AuthRepository {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<AuthToken> login(String username, String password) async {
    final response = await dio.post(
      '/api/auth/login',
      data: FormData.fromMap({'username': username, 'password': password}),
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    return AuthToken.fromJson(response.data);
  }

  Future<void> saveToken(String token) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.tokenKey, token);
  }

  Future<void> saveUser(Map<String, dynamic> user) async {
    final prefs = await _prefs;
    await prefs.setString(AppConstants.userKey, jsonEncode(user));
  }

  Future<String?> getToken() async {
    final prefs = await _prefs;
    return prefs.getString(AppConstants.tokenKey);
  }

  Future<Map<String, dynamic>?> getSavedUser() async {
    final prefs = await _prefs;
    final raw = prefs.getString(AppConstants.userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> logout() async {
    final prefs = await _prefs;
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
  }
}
