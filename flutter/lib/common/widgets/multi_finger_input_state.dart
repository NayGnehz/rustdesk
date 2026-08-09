class SpecialHoldDragUpdate {
  const SpecialHoldDragUpdate._({
    required this.handled,
    required this.deltaX,
    required this.deltaY,
  });

  const SpecialHoldDragUpdate.notHandled()
      : this._(handled: false, deltaX: 0, deltaY: 0);

  const SpecialHoldDragUpdate.handled(double deltaX, double deltaY)
      : this._(handled: true, deltaX: deltaX, deltaY: deltaY);

  final bool handled;
  final double deltaX;
  final double deltaY;
}

class MultiFingerScrollUpdate {
  const MultiFingerScrollUpdate({
    required this.specialHoldDrag,
    required this.scrollDirection,
  });

  final SpecialHoldDragUpdate specialHoldDrag;
  final int scrollDirection;
}

class MultiFingerInputState {
  double _scrollIntegral = 0;
  double _scale = 1;
  bool _specialHoldDragInProgress = false;
  double _lastSpecialFocalX = 0;
  double _lastSpecialFocalY = 0;

  bool get isSpecialHoldDragInProgress => _specialHoldDragInProgress;

  void startScroll() {
    _scrollIntegral = 0;
  }

  int updateScroll(double deltaY) {
    _scrollIntegral += deltaY / 4;
    if (_scrollIntegral > 1) {
      _scrollIntegral = 0;
      return 1;
    }
    if (_scrollIntegral < -1) {
      _scrollIntegral = 0;
      return -1;
    }
    return 0;
  }

  MultiFingerScrollUpdate routeScrollUpdate({
    required bool specialHoldDragActive,
    required double focalX,
    required double focalY,
    required double deltaY,
  }) {
    final specialHoldDrag = updateSpecialHoldDrag(
      specialHoldDragActive: specialHoldDragActive,
      focalX: focalX,
      focalY: focalY,
    );
    return MultiFingerScrollUpdate(
      specialHoldDrag: specialHoldDrag,
      scrollDirection: specialHoldDrag.handled ? 0 : updateScroll(deltaY),
    );
  }

  void endScroll() {
    _scrollIntegral = 0;
  }

  void startScale() {
    _scale = 1;
  }

  double updateScale(double scale) {
    final ratio = scale / _scale;
    _scale = scale;
    return ratio;
  }

  void endScale() {
    _scale = 1;
  }

  bool startGesture({
    required bool specialHoldDragActive,
    required double focalX,
    required double focalY,
  }) {
    _specialHoldDragInProgress = specialHoldDragActive;
    if (_specialHoldDragInProgress) {
      _lastSpecialFocalX = focalX;
      _lastSpecialFocalY = focalY;
    }
    return !_specialHoldDragInProgress;
  }

  SpecialHoldDragUpdate updateSpecialHoldDrag({
    required bool specialHoldDragActive,
    required double focalX,
    required double focalY,
  }) {
    if (!_specialHoldDragInProgress && specialHoldDragActive) {
      _specialHoldDragInProgress = true;
      _lastSpecialFocalX = focalX;
      _lastSpecialFocalY = focalY;
      return const SpecialHoldDragUpdate.handled(0, 0);
    }
    if (!_specialHoldDragInProgress) {
      return const SpecialHoldDragUpdate.notHandled();
    }
    final deltaX = (focalX - _lastSpecialFocalX) * 2;
    final deltaY = (focalY - _lastSpecialFocalY) * 2;
    _lastSpecialFocalX = focalX;
    _lastSpecialFocalY = focalY;
    return SpecialHoldDragUpdate.handled(deltaX, deltaY);
  }

  bool endOrCancelGesture({required bool specialHoldDragActive}) {
    final allowGenericLeftButtonRelease =
        !_specialHoldDragInProgress && !specialHoldDragActive;
    _specialHoldDragInProgress = false;
    _lastSpecialFocalX = 0;
    _lastSpecialFocalY = 0;
    return allowGenericLeftButtonRelease;
  }
}
