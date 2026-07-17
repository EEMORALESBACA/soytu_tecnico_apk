// Smoke test de la pantalla de login. No inicializa Firebase (no hay
// proyecto real en el entorno de pruebas): solo verifica que la UI se
// construye y valida el formulario sin necesitar sesión.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soytu_tecnico_apk/auth/login_screen.dart';

void main() {
  testWidgets('LoginScreen muestra el formulario de acceso', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    ));

    expect(find.text('Acceso Técnico'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Entrar'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Entrar'));
    await tester.pump();

    expect(find.text('Correo inválido'), findsOneWidget);
  });
}
