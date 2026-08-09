import 'package:flutter_hbb/common/widgets/multi_finger_input_state.dart';
import 'package:flutter_test/flutter_test.dart';

enum _SpecialButton { left, right }

enum _Termination { end, cancel }

void main() {
  test('scroll residual resets at gesture start and end', () {
    final state = MultiFingerInputState();

    state.startScroll();
    expect(state.updateScroll(3.9), 0);
    state.endScroll();
    state.startScroll();
    expect(state.updateScroll(0.2), 0);

    expect(state.updateScroll(3.7), 0);
    state.startScroll();
    expect(state.updateScroll(0.2), 0);
  });

  test('scroll threshold preserves vertical direction', () {
    final state = MultiFingerInputState();

    state.startScroll();
    expect(state.updateScroll(4), 0);
    expect(state.updateScroll(0.1), 1);

    state.startScroll();
    expect(state.updateScroll(-4), 0);
    expect(state.updateScroll(-0.1), -1);
  });

  test('scale baseline resets and returns consecutive ratios', () {
    final state = MultiFingerInputState();

    state.startScale();
    expect(state.updateScale(1.2), closeTo(1.2, 0.000001));
    expect(state.updateScale(1.5), closeTo(1.25, 0.000001));
    state.endScale();

    state.startScale();
    expect(state.updateScale(0.8), closeTo(0.8, 0.000001));
  });

  test('normal gesture allows generic left button release', () {
    final state = MultiFingerInputState();

    expect(
      state.startGesture(
        specialHoldDragActive: false,
        focalX: 10,
        focalY: 20,
      ),
      isTrue,
    );
    expect(
      state.endOrCancelGesture(specialHoldDragActive: false),
      isTrue,
    );
  });

  for (final button in _SpecialButton.values) {
    for (final termination in _Termination.values) {
      test('special ${button.name} owns release when ${termination.name} wins',
          () {
        final state = MultiFingerInputState();

        expect(
          state.startGesture(
            specialHoldDragActive: true,
            focalX: 10,
            focalY: 20,
          ),
          isFalse,
        );

        // The button can release before the gesture boundary is delivered.
        expect(
          state.endOrCancelGesture(specialHoldDragActive: false),
          isFalse,
        );
      });
    }
  }

  test('special owner also blocks cleanup before the button releases', () {
    final state = MultiFingerInputState();

    state.startGesture(
      specialHoldDragActive: true,
      focalX: 10,
      focalY: 20,
    );

    expect(
      state.endOrCancelGesture(specialHoldDragActive: true),
      isFalse,
    );
  });

  test('special hold activation at a boundary consumes the first update', () {
    final state = MultiFingerInputState();

    state.startScroll();
    state.startGesture(
      specialHoldDragActive: false,
      focalX: 10,
      focalY: 20,
    );

    final firstUpdate = state.routeScrollUpdate(
      specialHoldDragActive: true,
      focalX: 40,
      focalY: 60,
      deltaY: 8,
    );
    expect(firstUpdate.specialHoldDrag.handled, isTrue);
    expect(firstUpdate.specialHoldDrag.deltaX, 0);
    expect(firstUpdate.specialHoldDrag.deltaY, 0);
    expect(firstUpdate.scrollDirection, 0);

    final panUpdate = state.updateSpecialHoldDrag(
      specialHoldDragActive: true,
      focalX: 43,
      focalY: 55,
    );
    expect(panUpdate.handled, isTrue);
    expect(panUpdate.deltaX, 6);
    expect(panUpdate.deltaY, -10);
    expect(
      state.endOrCancelGesture(specialHoldDragActive: false),
      isFalse,
    );
  });
}
