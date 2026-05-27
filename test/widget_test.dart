// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app_secretaria/main.dart';
import 'package:app_secretaria/models/report_model.dart';
import 'package:app_secretaria/screens/login_screen.dart';
import 'package:app_secretaria/utils/app_version.dart';
import 'package:app_secretaria/utils/app_constants.dart';
import 'package:app_secretaria/utils/text_encoding.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AppSecretaria());
    await tester.pump();

    expect(find.byType(AppSecretaria), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Versão ${AppVersion.version}'), findsOneWidget);
  });

  test('repairs mojibake and keeps technicians aliases', () {
    expect(fixMojibake('JoÃ£o Pessoa'), 'João Pessoa');
    expect(fixMojibake('CatolÃ© do Rocha'), 'Catolé do Rocha');
    expect(Constants.regionals.first, '01ª GRE (João Pessoa)');

    final report = ReportModel.fromJson({
      'id': '1',
      'schoolName': 'Escola Teste',
      'visitDate': '2026-05-25T12:00:00.000',
      'Técnicos Presentes': 'Jarley Soares da Costa, José de Sena Brito Junior',
      'gre': '01Âª GRE (JoÃ£o Pessoa)',
      'municipio': 'JoÃ£o Pessoa',
    });

    expect(report.gre, '01ª GRE (João Pessoa)');
    expect(report.schoolCity, 'João Pessoa');
    expect(report.technicians, ['Jarley Soares da Costa', 'José de Sena Brito Junior']);
  });
}
