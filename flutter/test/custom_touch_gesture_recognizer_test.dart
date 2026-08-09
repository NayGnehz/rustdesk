import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common/widgets/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

ScaleUpdateDetails _updateDetails(int pointerCount) {
  return ScaleUpdateDetails(
    focalPoint: const Offset(20, 30),
    localFocalPoint: const Offset(10, 15),
    focalPointDelta: const Offset(0, 4),
    pointerCount: pointerCount,
  );
}

void _update(CustomTouchGestureRecognizer recognizer, int pointerCount) {
  recognizer.onUpdate!.call(_updateDetails(pointerCount));
}

void main() {
  test('resolveMultiFingerGestureMode scopes the Android gesture mapping', () {
    expect(
      resolveMultiFingerGestureMode(
        isAndroidController: true,
        isCamera: false,
        isPeerAndroid: false,
      ),
      MultiFingerGestureMode.twoFingerScrollThreeFingerScale,
    );
    expect(
      resolveMultiFingerGestureMode(
        isAndroidController: false,
        isCamera: false,
        isPeerAndroid: false,
      ),
      MultiFingerGestureMode.legacy,
    );
    expect(
      resolveMultiFingerGestureMode(
        isAndroidController: true,
        isCamera: true,
        isPeerAndroid: false,
      ),
      MultiFingerGestureMode.legacy,
    );
    expect(
      resolveMultiFingerGestureMode(
        isAndroidController: true,
        isCamera: false,
        isPeerAndroid: true,
      ),
      MultiFingerGestureMode.legacy,
    );
  });

  test('help keys describe the selected mapping in both input modes', () {
    final updated = resolveMultiFingerGestureHelpKeys(
        MultiFingerGestureMode.twoFingerScrollThreeFingerScale);
    expect(updated.scroll, 'Two-finger vertical swipe');
    expect(updated.move, 'Three-finger move');
    expect(updated.zoom, 'Three-finger pinch');

    final legacy =
        resolveMultiFingerGestureHelpKeys(MultiFingerGestureMode.legacy);
    expect(legacy.scroll, 'Three-Finger vertically');
    expect(legacy.move, 'Two-Finger Move');
    expect(legacy.zoom, 'Pinch to Zoom');
  });

  testWidgets('legacy mode keeps two-finger scale and three-finger drag',
      (_) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer();
    recognizer.onTwoFingerScaleStart = (_) => events.add('two-scale-start');
    recognizer.onTwoFingerScaleUpdate = (_) => events.add('two-scale-update');
    recognizer.onTwoFingerScaleEnd = (_) => events.add('two-scale-end');
    recognizer.onThreeFingerVerticalDragStart =
        (_) => events.add('three-drag-start');
    recognizer.onThreeFingerVerticalDragUpdate =
        (_) => events.add('three-drag-update');
    recognizer.onThreeFingerVerticalDragEnd =
        (_) => events.add('three-drag-end');
    recognizer.onTwoFingerScrollStart = (_) => events.add('unexpected-scroll');
    recognizer.onThreeFingerScaleStart =
        (_) => events.add('unexpected-three-scale');
    addTearDown(recognizer.dispose);

    expect(recognizer.multiFingerGestureMode, MultiFingerGestureMode.legacy);
    _update(recognizer, 2);
    _update(recognizer, 3);
    recognizer.onEnd!.call(ScaleEndDetails());

    expect(events, <String>[
      'two-scale-start',
      'two-scale-update',
      'two-scale-end',
      'three-drag-start',
      'three-drag-update',
      'three-drag-end',
    ]);
  });

  testWidgets('new mode exits and enters immediately across 2-3-2', (_) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer(
      multiFingerGestureMode:
          MultiFingerGestureMode.twoFingerScrollThreeFingerScale,
    );
    recognizer.onTwoFingerScrollStart = (_) => events.add('scroll-start');
    recognizer.onTwoFingerScrollUpdate = (_) => events.add('scroll-update');
    recognizer.onTwoFingerScrollEnd = (_) => events.add('scroll-end');
    recognizer.onThreeFingerScaleStart = (_) => events.add('scale-start');
    recognizer.onThreeFingerScaleUpdate = (_) => events.add('scale-update');
    recognizer.onThreeFingerScaleEnd = (_) => events.add('scale-end');
    addTearDown(recognizer.dispose);

    _update(recognizer, 2);
    recognizer.onEnd!.call(ScaleEndDetails(pointerCount: 3));
    _update(recognizer, 3);
    recognizer.onEnd!.call(ScaleEndDetails(pointerCount: 2));
    _update(recognizer, 2);
    recognizer.onEnd!.call(ScaleEndDetails());

    expect(events, <String>[
      'scroll-start',
      'scroll-update',
      'scroll-end',
      'scale-start',
      'scale-update',
      'scale-end',
      'scroll-start',
      'scroll-update',
      'scroll-end',
    ]);
  });

  testWidgets(
      'multi-finger to one-finger waits without dispatching the old state',
      (tester) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer(
      multiFingerGestureMode:
          MultiFingerGestureMode.twoFingerScrollThreeFingerScale,
    );
    recognizer.onTwoFingerScrollStart = (_) => events.add('scroll-start');
    recognizer.onTwoFingerScrollUpdate = (_) => events.add('scroll-update');
    recognizer.onTwoFingerScrollEnd = (_) => events.add('scroll-end');
    recognizer.onOneFingerPanStart = (_) => events.add('pan-start');
    recognizer.onOneFingerPanUpdate = (_) => events.add('pan-update');
    recognizer.onOneFingerPanEnd = (_) => events.add('pan-end');
    addTearDown(recognizer.dispose);

    _update(recognizer, 2);
    recognizer.onEnd!.call(ScaleEndDetails(pointerCount: 1));
    _update(recognizer, 1);
    _update(recognizer, 1);

    expect(events, <String>[
      'scroll-start',
      'scroll-update',
      'scroll-end',
    ]);

    await tester.pump(const Duration(milliseconds: 199));
    expect(events, isNot(contains('pan-start')));
    await tester.pump(const Duration(milliseconds: 1));
    expect(events.last, 'pan-start');

    _update(recognizer, 1);
    recognizer.onEnd!.call(ScaleEndDetails());
    expect(
        events.sublist(events.length - 2), <String>['pan-update', 'pan-end']);
  });

  testWidgets('four or more fingers exit the active state and are ignored',
      (tester) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer(
      multiFingerGestureMode:
          MultiFingerGestureMode.twoFingerScrollThreeFingerScale,
    );
    recognizer.onThreeFingerScaleStart = (_) => events.add('scale-start');
    recognizer.onThreeFingerScaleUpdate = (_) => events.add('scale-update');
    recognizer.onThreeFingerScaleEnd = (_) => events.add('scale-end');
    recognizer.onOneFingerPanStart = (_) => events.add('pan-start');
    recognizer.onOneFingerPanUpdate = (_) => events.add('pan-update');
    addTearDown(recognizer.dispose);

    _update(recognizer, 3);
    recognizer.onEnd!.call(ScaleEndDetails(pointerCount: 4));
    _update(recognizer, 4);
    _update(recognizer, 5);
    expect(events, <String>['scale-start', 'scale-update', 'scale-end']);

    _update(recognizer, 1);
    await tester.pump(const Duration(milliseconds: 199));
    expect(events, isNot(contains('pan-start')));
    await tester.pump(const Duration(milliseconds: 1));
    expect(events.last, 'pan-start');

    _update(recognizer, 4);
    _update(recognizer, 3);
    expect(events.sublist(events.length - 2),
        <String>['scale-start', 'scale-update']);
  });

  testWidgets('four-finger first update still defers one-finger pan',
      (tester) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer(
      multiFingerGestureMode:
          MultiFingerGestureMode.twoFingerScrollThreeFingerScale,
    );
    recognizer.onOneFingerPanStart = (_) => events.add('pan-start');
    recognizer.onOneFingerPanUpdate = (_) => events.add('pan-update');
    addTearDown(recognizer.dispose);

    _update(recognizer, 4);
    _update(recognizer, 1);

    await tester.pump(const Duration(milliseconds: 199));
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(events, <String>['pan-start']);
  });

  testWidgets('one-finger to two-finger exits before entering multi-finger',
      (_) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer(
      multiFingerGestureMode:
          MultiFingerGestureMode.twoFingerScrollThreeFingerScale,
    );
    recognizer.onOneFingerPanStart = (_) => events.add('pan-start');
    recognizer.onOneFingerPanUpdate = (_) => events.add('pan-update');
    recognizer.onOneFingerPanEnd = (_) => events.add('pan-end');
    recognizer.onTwoFingerScrollStart = (_) => events.add('scroll-start');
    recognizer.onTwoFingerScrollUpdate = (_) => events.add('scroll-update');
    addTearDown(recognizer.dispose);

    _update(recognizer, 1);
    recognizer.onEnd!.call(ScaleEndDetails(pointerCount: 2));
    _update(recognizer, 2);

    expect(events, <String>[
      'pan-start',
      'pan-update',
      'pan-end',
      'scroll-start',
      'scroll-update',
    ]);
  });

  testWidgets('one-finger rejection reports cancel instead of end', (_) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer();
    recognizer.onOneFingerPanStart = (_) => events.add('pan-start');
    recognizer.onOneFingerPanUpdate = (_) => events.add('pan-update');
    recognizer.onOneFingerPanEnd = (_) => events.add('pan-end');
    recognizer.onOneFingerPanCancel = () => events.add('pan-cancel');
    addTearDown(recognizer.dispose);

    _update(recognizer, 1);
    recognizer.rejectGesture(1);

    expect(events, <String>['pan-start', 'pan-update', 'pan-cancel']);
  });

  testWidgets('gesture rejection cleans up active and pending states',
      (tester) async {
    final events = <String>[];
    final recognizer = CustomTouchGestureRecognizer(
      multiFingerGestureMode:
          MultiFingerGestureMode.twoFingerScrollThreeFingerScale,
    );
    recognizer.onTwoFingerScrollStart = (_) => events.add('scroll-start');
    recognizer.onTwoFingerScrollUpdate = (_) => events.add('scroll-update');
    recognizer.onTwoFingerScrollEnd = (_) => events.add('scroll-end');
    recognizer.onOneFingerPanStart = (_) => events.add('pan-start');
    addTearDown(recognizer.dispose);

    _update(recognizer, 2);
    _update(recognizer, 1);
    recognizer.rejectGesture(1);
    await tester.pump(const Duration(milliseconds: 250));

    expect(events, <String>[
      'scroll-start',
      'scroll-update',
      'scroll-end',
    ]);

    _update(recognizer, 2);
    recognizer.rejectGesture(2);
    expect(events.last, 'scroll-end');
  });
}
