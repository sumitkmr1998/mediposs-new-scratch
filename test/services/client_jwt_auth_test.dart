import 'package:flutter_test/flutter_test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

void main() {
  test('Client fallback JWT is signed with jwtSecret and verified by Hub', () {
    const hubSecret = 'medipos_secret_key_2024';

    // Simulate Android companion signing fallback token
    final jwt = JWT(
      {
        'userId': 1,
        'role': 'admin',
        'name': 'Client Sync',
      },
      issuer: 'mediposs_client',
    );
    final token = jwt.sign(SecretKey(hubSecret), expiresIn: const Duration(days: 30));

    expect(token, isNotEmpty);

    // Simulate Old Hub verifying the token
    final verified = JWT.verify(token, SecretKey(hubSecret));
    final payload = verified.payload as Map<String, dynamic>;

    expect(payload['userId'], equals(1));
    expect(payload['role'], equals('admin'));
    expect(payload['name'], equals('Client Sync'));
  });

  test('Cloud token string fails JWT.verify so fallback must be used', () {
    const hubSecret = 'medipos_secret_key_2024';
    final dummyCloudToken = 'cloud_token_${DateTime.now().millisecondsSinceEpoch}';

    expect(
      () => JWT.verify(dummyCloudToken, SecretKey(hubSecret)),
      throwsA(isA<JWTException>()),
    );
  });
}

