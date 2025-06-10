import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CredentialManager {
  static const _storage = FlutterSecureStorage();
  
  static Future<void> saveCredentials(String username, String password) async {
    await _storage.write(key: 'api_username', value: username);
    await _storage.write(key: 'api_password', value: password);
  }
  
  static Future<Map<String, String>?> getCredentials() async {
    final username = await _storage.read(key: 'api_username');
    final password = await _storage.read(key: 'api_password');
    
    if (username != null && password != null) {
      return {'username': username, 'password': password};
    }
    return null;
  }
  
  static Future<void> clearCredentials() async {
    await _storage.delete(key: 'api_username');
    await _storage.delete(key: 'api_password');
  }
  
  static Future<bool> hasCredentials() async {
    return await _storage.containsKey(key: 'api_username') &&
           await _storage.containsKey(key: 'api_password');
  }
}