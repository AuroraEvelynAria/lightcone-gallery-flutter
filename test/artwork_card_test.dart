import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/ui/artwork_card.dart';

final _onePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('作品卡：标题 / 画师 / 页角标，心不触发整卡', (tester) async {
    var cardTaps = 0;
    var heartTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: ArtworkCard(
                image: MemoryImage(_onePixel),
                aspectRatio: 0.75,
                title: '一张作品的标题',
                artist: '画师名',
                favorite: false,
                pageCount: 3,
                onTap: () => cardTaps++,
                onFavorite: () => heartTaps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('一张作品的标题'), findsOneWidget);
    expect(find.text('画师名'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    expect(heartTaps, 1);
    expect(cardTaps, 0, reason: '点心只切收藏，不该打开详情');

    await tester.tap(find.text('一张作品的标题'));
    expect(cardTaps, 1);
  });

  testWidgets('已收藏显示实心红心', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              child: ArtworkCard(
                image: MemoryImage(_onePixel),
                aspectRatio: 0.75,
                title: 't',
                artist: 'a',
                favorite: true,
                onTap: () {},
                onFavorite: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });
}
