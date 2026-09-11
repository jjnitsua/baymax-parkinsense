import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/aws_config.dart';
import '../../models/user.dart';
import '../../repositories/auth_repository.dart';

class AwsAuthRepository implements AuthRepository {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _kUsername = 'cognito_username';
  static const _kIdToken = 'cognito_id_token';
  static const _kAccessToken = 'cognito_access_token';
  static const _kRefreshToken = 'cognito_refresh_token';

  final _pool = CognitoUserPool(AwsConfig.userPoolId, AwsConfig.clientId);

  CognitoUser? _cognitoUser;
  CognitoUserSession? _session;
  String? _username;

  /// Returns a valid ID token, silently refreshing the session when expired.
  Future<String> getIdToken() async {
    if (_session == null || _cognitoUser == null) {
      throw Exception('Not signed in');
    }
    if (!_session!.isValid()) {
      _session =
          await _cognitoUser!.refreshSession(_session!.refreshToken!);
      if (_session == null) throw Exception('Session refresh failed');
      if (_username != null) await _persistTokens(_username!, _session!);
    }
    return _session!.idToken.jwtToken!;
  }

  @override
  Future<User> signIn(String email, String password) async {
    _username = email.trim();
    _cognitoUser = CognitoUser(_username!, _pool);
    final authDetails = AuthenticationDetails(
      username: _username!,
      password: password,
    );
    try {
      _session = await _cognitoUser!.authenticateUser(authDetails);
    } on CognitoClientException catch (e) {
      throw Exception(e.message ?? 'Authentication failed');
    } on CognitoUserException catch (e) {
      throw Exception(e.message ?? 'Authentication failed');
    }
    if (_session == null) throw Exception('Authentication failed');
    await _persistTokens(_username!, _session!);
    return User.fromJson(_session!.idToken.payload);
  }

  /// Attempts to restore a persisted session on app startup.
  /// Returns the authenticated [User], or null if no valid session exists.
  Future<User?> restoreSession() async {
    final username = await _storage.read(key: _kUsername);
    final idToken = await _storage.read(key: _kIdToken);
    final accessToken = await _storage.read(key: _kAccessToken);
    final refreshToken = await _storage.read(key: _kRefreshToken);

    if (username == null || idToken == null || accessToken == null) {
      return null;
    }

    _username = username;
    _cognitoUser = CognitoUser(username, _pool);
    _session = CognitoUserSession(
      CognitoIdToken(idToken),
      CognitoAccessToken(accessToken),
      refreshToken:
          refreshToken != null ? CognitoRefreshToken(refreshToken) : null,
    );

    try {
      if (!_session!.isValid()) {
        if (refreshToken == null) {
          await _clearTokens();
          return null;
        }
        _session =
            await _cognitoUser!.refreshSession(_session!.refreshToken!);
        if (_session == null) {
          await _clearTokens();
          return null;
        }
        await _persistTokens(username, _session!);
      }
      return User.fromJson(_session!.idToken.payload);
    } catch (_) {
      await _clearTokens();
      _cognitoUser = null;
      _session = null;
      _username = null;
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    await _cognitoUser?.signOut();
    await _clearTokens();
    _cognitoUser = null;
    _session = null;
    _username = null;
  }

  Future<void> _persistTokens(
      String username, CognitoUserSession session) async {
    await Future.wait([
      _storage.write(key: _kUsername, value: username),
      _storage.write(key: _kIdToken, value: session.idToken.jwtToken),
      _storage.write(
          key: _kAccessToken, value: session.accessToken.jwtToken),
      if (session.refreshToken?.token != null)
        _storage.write(
            key: _kRefreshToken, value: session.refreshToken!.token),
    ]);
  }

  Future<void> _clearTokens() async {
    await Future.wait([
      _storage.delete(key: _kUsername),
      _storage.delete(key: _kIdToken),
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
    ]);
  }
}
