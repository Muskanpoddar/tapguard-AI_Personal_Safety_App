// test/risk/audio_collector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tapguard/data/services/risk/audio_collector.dart';

void main() {
  group('AudioCollector (Phase 2)', () {
    test('starts in model-not-loaded state', () {
      final c = AudioCollector();
      expect(c.modelLoaded, false);
      expect(c.isRunning, false);
    });

    test('loadKeywordModel() silently fails when model file is missing',
        () async {
      final c = AudioCollector();
      final loaded = await c.loadKeywordModel();
      expect(loaded, false);
      expect(c.modelLoaded, false);
    });

    test('activeKeywords lists non-silence labels', () {
      final c = AudioCollector();
      final words = c.activeKeywords;
      expect(words, containsAll(['help', 'stop', 'danger']));
      expect(words, isNot(contains('silence')));
    });

    test('publishHit emits a KeywordHit on the stream', () async {
      final c = AudioCollector();
      final hits = <KeywordHit>[];
      final sub = c.keywordStream.listen(hits.add);
      c.publishHit('help', 0.92);
      // Allow microtasks to flush
      await Future.delayed(Duration.zero);
      expect(hits.length, 1);
      expect(hits.first.keyword, 'help');
      expect(hits.first.confidence, closeTo(0.92, 0.001));
      await sub.cancel();
    });
  });
}
