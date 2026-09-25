// Kept in the repo on purpose: CI runs `flutter create .`, which would
// otherwise regenerate Flutter's template test (it references a `MyApp`
// class this project doesn't have, and fails to compile).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wave_rush/game/levels.dart';
import 'package:wave_rush/screens/level_select_screen.dart';
import 'package:wave_rush/screens/my_levels_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('level select shows the first level card', (tester) async {
    tester.view.physicalSize = const Size(844 * 3, 390 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LevelSelectScreen()));
    await tester.pumpAndSettle();
    expect(find.text('SELECT LEVEL'), findsOneWidget);
    expect(find.text(kLevels.first.name), findsOneWidget);
  });

  testWidgets('my levels starts empty with NEW and IMPORT', (tester) async {
    tester.view.physicalSize = const Size(844 * 3, 390 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: MyLevelsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('IMPORT'), findsOneWidget);
    expect(find.textContaining('No levels yet'), findsOneWidget);
  });
}
