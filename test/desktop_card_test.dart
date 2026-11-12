import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/ui/artwork_card.dart';

final _onePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 围绕桌面壳新增的两处交互：作品卡的右键菜单回调、鼠标悬停态。
/// 手机端（不传 onContextMenu）必须保持「右键=长按」的老语义。
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      );

  Widget card({
    void Function(Offset)? onContextMenu,
    VoidCallback? onLongPress,
    VoidCallback? onFavorite,
    VoidCallback? onTap,
    void Function(ArtworkTapModifiers)? onTapModified,
  }) =>
      SizedBox(
        width: 220,
        child: ArtworkCard(
          image: MemoryImage(_onePixel),
          aspectRatio: 0.75,
          title: 't',
          artist: 'a',
          favorite: false,
          onTap: onTap ?? () {},
          onFavorite: onFavorite,
          onLongPress: onLongPress,
          onContextMenu: onContextMenu,
          onTapModified: onTapModified,
        ),
      );

  testWidgets('给了 onContextMenu：右键触发它，并带上全局坐标', (tester) async {
    Offset? captured;
    await tester.pumpWidget(host(card(onContextMenu: (p) => captured = p)));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ArtworkCard)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(captured, isNotNull, reason: '右键应把坐标交给上下文菜单');
    expect(captured!.dx, greaterThan(0));
  });

  testWidgets('没给 onContextMenu：右键退回长按语义（手机端）', (tester) async {
    var longPresses = 0;
    await tester.pumpWidget(host(card(onLongPress: () => longPresses++)));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ArtworkCard)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(longPresses, 1);
  });

  testWidgets('鼠标进入卡片时描边高亮（悬停态）', (tester) async {
    await tester.pumpWidget(host(card(onFavorite: () {})));
    await tester.pump();

    Material material() => tester.widget<Material>(
          find
              .descendant(
                of: find.byType(ArtworkCard),
                matching: find.byType(Material),
              )
              .first,
        );
    expect(material().elevation, 0);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(ArtworkCard))),
    );
    await tester.pumpAndSettle();
    expect(material().elevation, greaterThan(0), reason: '悬停应抬升卡片');

    await tester.sendEventToBinding(
      pointer.hover(const Offset(2000, 2000)),
    );
    await tester.pumpAndSettle();
    expect(material().elevation, 0, reason: '移出应复位');
  });

  testWidgets('给了 onTapModified：普通点击带 ctrl=false/shift=false', (tester) async {
    ArtworkTapModifiers? captured;
    var plainTaps = 0;
    await tester.pumpWidget(
      host(card(onTap: () => plainTaps++, onTapModified: (m) => captured = m)),
    );
    await tester.pump();

    await tester.tap(find.byType(ArtworkCard));
    await tester.pump();

    expect(captured, isNotNull, reason: '桌面上点击应带上修饰键状态');
    expect(captured, (ctrl: false, shift: false));
    expect(plainTaps, 0, reason: '给了 onTapModified 就不该再触发 onTap');
  });

  testWidgets('按住 Ctrl 点击：onTapModified 收到 ctrl=true', (tester) async {
    ArtworkTapModifiers? captured;
    await tester.pumpWidget(host(card(onTapModified: (m) => captured = m)));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byType(ArtworkCard));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(captured, (ctrl: true, shift: false));
  });

  testWidgets('按住 Shift 点击：onTapModified 收到 shift=true', (tester) async {
    ArtworkTapModifiers? captured;
    await tester.pumpWidget(host(card(onTapModified: (m) => captured = m)));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byType(ArtworkCard));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(captured, (ctrl: false, shift: true));
  });
}
