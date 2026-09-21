// How backend failures are turned into something a person can read.
//
// Written after a real incident: signing up with a short password returned a
// FastAPI 422 whose `detail` is a *list* of field errors, not a string. That
// case was unhandled, so the red box showed the raw JSON blob and the actual
// problem ("password must be at least 8 characters") was invisible.
import 'package:flutter_test/flutter_test.dart';
import 'package:handled_app/services/api_service.dart';

void main() {
  group('friendlyError', () {
    test('pulls the field and reason out of a FastAPI 422', () {
      // Verbatim shape returned by the backend for a too-short password.
      final e = Exception(
        'API Error 422: {"detail":[{"type":"string_too_short",'
        '"loc":["body","password"],"msg":"String should have at least 8 characters",'
        '"input":"abc","ctx":{"min_length":8}}]}',
      );
      final msg = ApiService.friendlyError(e);
      expect(msg, contains('password'));
      expect(msg, contains('at least 8 characters'));
      // The raw payload must not leak through.
      expect(msg, isNot(contains('string_too_short')));
      expect(msg, isNot(contains('"loc"')));
    });

    test('lists every field when several fail at once', () {
      final e = Exception(
        'API Error 422: {"detail":['
        '{"loc":["body","name"],"msg":"Field required"},'
        '{"loc":["body","password"],"msg":"String should have at least 8 characters"}]}',
      );
      final msg = ApiService.friendlyError(e);
      expect(msg, contains('name'));
      expect(msg, contains('password'));
    });

    test('uses the plain detail string when the API sends one', () {
      final e = Exception(
        'API Error 400: {"detail":"An account with this email already exists."}',
      );
      expect(
        ApiService.friendlyError(e),
        'An account with this email already exists.',
      );
    });

    test('says the server is unreachable rather than showing a socket error', () {
      expect(
        ApiService.friendlyError(Exception('ClientException: Failed to fetch, uri=...')),
        contains("Can't reach the server"),
      );
    });

    test('falls back to the message when the body is not JSON', () {
      final msg = ApiService.friendlyError(Exception('API Error 500: Internal Server Error'));
      expect(msg, contains('Internal Server Error'));
      // The "Exception: " prefix is noise to a user.
      expect(msg, isNot(startsWith('Exception:')));
    });
  });
}
