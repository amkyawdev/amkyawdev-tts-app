import 'package:amkyaw_tts_studio/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('PageHeader renders the studio identity', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageHeader(
            eyebrow: 'AmkyawDev',
            title: 'TTS Studio',
            subtitle: 'Hybrid speech synthesis',
          ),
        ),
      ),
    );

    expect(find.text('TTS Studio'), findsOneWidget);
    expect(find.text('AMKYAWDEV'), findsOneWidget);
    expect(find.text('Hybrid speech synthesis'), findsOneWidget);
  });

  testWidgets('StatusDot renders with an accessible size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: StatusDot(color: Colors.green)),
        ),
      ),
    );

    final dot = tester.widget<StatusDot>(find.byType(StatusDot));
    expect(dot.color, Colors.green);
    expect(find.byType(StatusDot), findsOneWidget);
  });
}
