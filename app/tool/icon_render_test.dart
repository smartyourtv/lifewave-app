// Icon render harness — NOT a unit test. It rasterizes the OFFICIAL
// LifeWave logo SVG (assets/brand/lifewave-logo.svg) into the launcher
// icon source PNGs under assets/icon/, using Flutter's own SVG renderer,
// so the icon is the real logo artwork, never a redraw.
//
// Run it with:
//   cp tool/icon_render_test.dart test/icon_render_test.dart
//   flutter test test/icon_render_test.dart
//   rm test/icon_render_test.dart
// then:
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String outPath,
) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(outPath).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render launcher icon PNGs from the official logo',
      (tester) async {
    final root = Directory.current.path;
    final keyMain = GlobalKey();
    final keyFg = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RepaintBoundary(
                key: keyMain,
                child: Container(
                  width: 512,
                  height: 512,
                  color: const Color(0xFFECF5FA), // palette tint panel
                  alignment: Alignment.center,
                  child: SvgPicture.asset(
                    'assets/brand/lifewave-logo.svg',
                    width: 430,
                  ),
                ),
              ),
              RepaintBoundary(
                key: keyFg,
                child: SizedBox(
                  width: 512,
                  height: 512,
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/brand/lifewave-logo.svg',
                      width: 330,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _capture(tester, keyMain, '$root/assets/icon/icon.png');
    await _capture(tester, keyFg, '$root/assets/icon/icon_foreground.png');
    expect(File('$root/assets/icon/icon.png').existsSync(), isTrue);
    expect(File('$root/assets/icon/icon_foreground.png').existsSync(), isTrue);
  });
}
