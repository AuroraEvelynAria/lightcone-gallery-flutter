import 'package:flutter_test/flutter_test.dart';
import 'package:lightcone_flutter/data/models.dart';

void main() {
  test('AI 标签按全名匹配，不误伤 Honkai', () {
    for (final tag in [
      'AI生成',
      'ai',
      'AIイラスト',
      'AI-generated',
      'ai-assisted',
      'AI绘画',
      'NovelAI',
    ]) {
      expect(looksLikeAiTag(tag), isTrue, reason: tag);
    }
    for (final tag in [
      'HonkaiStarRail',
      'Honkai',
      'pinkhair',
      'AI-generated-art', // 未收录的写法走保守路线，不误判
    ]) {
      expect(looksLikeAiTag(tag), isFalse, reason: tag);
    }
  });

  test('ArtworkDetail 的 AI 判定：Pixiv 标记或 AI 标签', () {
    ArtworkDetail detail({int aiType = 0, List<String> tags = const []}) =>
        ArtworkDetail(
          pid: '1',
          title: 't',
          artistUid: null,
          artistName: null,
          artistAccount: null,
          pageCount: 1,
          xRestrict: 0,
          createDate: null,
          tags: tags,
          pages: const [],
          favorite: false,
          aiType: aiType,
        );

    expect(detail(aiType: 2).isAiGenerated, isTrue);
    expect(detail(tags: const ['AI生成']).isAiGenerated, isTrue);
    expect(detail(tags: const ['HonkaiStarRail']).isAiGenerated, isFalse);
    expect(detail().isAiGenerated, isFalse);
  });
}
