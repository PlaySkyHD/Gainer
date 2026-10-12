import 'dart:convert';

class ApiSession {
  const ApiSession({
    required this.userId,
    required this.email,
    required this.isAccountOperator,
  });

  final String userId;
  final String email;
  final bool isAccountOperator;

  factory ApiSession.fromJson(Map<String, dynamic> json) => ApiSession(
    userId: _requiredString(json, 'userId'),
    email: _requiredString(json, 'email'),
    isAccountOperator: _requiredBool(json, 'isAccountOperator'),
  );
}

class ApiAntiforgeryToken {
  const ApiAntiforgeryToken(this.requestToken);

  final String requestToken;

  factory ApiAntiforgeryToken.fromJson(Map<String, dynamic> json) =>
      ApiAntiforgeryToken(_requiredString(json, 'requestToken'));
}

class ApiLoginRequest {
  const ApiLoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, Object?> toJson() => {'email': email, 'password': password};
}

class ApiAcceptInvitationRequest {
  const ApiAcceptInvitationRequest({
    required this.token,
    required this.password,
  });

  final String token;
  final String password;

  Map<String, Object?> toJson() => {'token': token, 'password': password};
}

class ApiAccountSummary {
  const ApiAccountSummary({
    required this.accountId,
    required this.email,
    required this.isActive,
  });

  final String accountId;
  final String email;
  final bool isActive;

  factory ApiAccountSummary.fromJson(Map<String, dynamic> json) =>
      ApiAccountSummary(
        accountId: _requiredString(json, 'accountId'),
        email: _requiredString(json, 'email'),
        isActive: _requiredBool(json, 'isActive'),
      );
}

class ApiInvitation {
  const ApiInvitation({required this.activationPath, required this.expiresAt});

  final String activationPath;
  final DateTime expiresAt;

  factory ApiInvitation.fromJson(Map<String, dynamic> json) => ApiInvitation(
    activationPath: _requiredString(json, 'activationPath'),
    expiresAt: DateTime.parse(_requiredString(json, 'expiresAt')).toUtc(),
  );
}

/// Error fields are read from both top-level API extensions and ProblemDetails.
class ApiProblem {
  const ApiProblem({this.title, this.detail, this.code});

  final String? title;
  final String? detail;
  final String? code;

  String get message => detail ?? title ?? 'Die Anfrage ist fehlgeschlagen.';

  factory ApiProblem.fromJson(Map<String, dynamic> json) {
    final extensions = json['extensions'];
    return ApiProblem(
      title: json['title'] as String?,
      detail: json['detail'] as String?,
      code:
          json['code'] as String? ??
          (extensions is Map<String, dynamic>
              ? extensions['code'] as String?
              : null),
    );
  }
}

Map<String, dynamic> decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected a JSON object.');
  }
  return decoded;
}

String _requiredString(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing or invalid "$name".');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String name) {
  final value = json[name];
  if (value is! bool) throw FormatException('Missing or invalid "$name".');
  return value;
}
