import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

enum MultiFingerGestureMode {
  legacy,
  twoFingerScrollThreeFingerScale,
}

class MultiFingerGestureHelpKeys {
  const MultiFingerGestureHelpKeys({
    required this.scroll,
    required this.move,
    required this.zoom,
  });

  final String scroll;
  final String move;
  final String zoom;
}

MultiFingerGestureHelpKeys resolveMultiFingerGestureHelpKeys(
    MultiFingerGestureMode mode) {
  if (mode == MultiFingerGestureMode.twoFingerScrollThreeFingerScale) {
    return const MultiFingerGestureHelpKeys(
      scroll: 'Two-finger vertical swipe',
      move: 'Three-finger move',
      zoom: 'Three-finger pinch',
    );
  }
  return const MultiFingerGestureHelpKeys(
    scroll: 'Three-Finger vertically',
    move: 'Two-Finger Move',
    zoom: 'Pinch to Zoom',
  );
}

MultiFingerGestureMode resolveMultiFingerGestureMode({
  required bool isAndroidController,
  required bool isCamera,
  required bool isPeerAndroid,
}) {
  if (isAndroidController && !isCamera && !isPeerAndroid) {
    return MultiFingerGestureMode.twoFingerScrollThreeFingerScale;
  }
  return MultiFingerGestureMode.legacy;
}

enum GestureState {
  none,
  oneFingerPan,
  twoFingerScale,
  threeFingerVerticalDrag,
  twoFingerScroll,
  threeFingerScale,
}

class CustomTouchGestureRecognizer extends ScaleGestureRecognizer {
  CustomTouchGestureRecognizer({
    Object? debugOwner,
    Set<PointerDeviceKind>? supportedDevices,
    this.multiFingerGestureMode = MultiFingerGestureMode.legacy,
  }) : super(
          debugOwner: debugOwner,
          supportedDevices: supportedDevices,
        ) {
    _init();
  }

  static const _multiToOneFingerDelay = Duration(milliseconds: 200);

  MultiFingerGestureMode multiFingerGestureMode;

  // oneFingerPan
  GestureDragStartCallback? onOneFingerPanStart;
  GestureDragUpdateCallback? onOneFingerPanUpdate;
  GestureDragEndCallback? onOneFingerPanEnd;
  GestureDragCancelCallback? onOneFingerPanCancel;

  // twoFingerScale : scale + pan event
  GestureScaleStartCallback? onTwoFingerScaleStart;
  GestureScaleUpdateCallback? onTwoFingerScaleUpdate;
  GestureScaleEndCallback? onTwoFingerScaleEnd;

  // twoFingerScroll
  GestureScaleStartCallback? onTwoFingerScrollStart;
  GestureScaleUpdateCallback? onTwoFingerScrollUpdate;
  GestureScaleEndCallback? onTwoFingerScrollEnd;

  // threeFingerVerticalDrag
  GestureDragStartCallback? onThreeFingerVerticalDragStart;
  GestureDragUpdateCallback? onThreeFingerVerticalDragUpdate;
  GestureDragEndCallback? onThreeFingerVerticalDragEnd;

  // threeFingerScale : scale + pan event
  GestureScaleStartCallback? onThreeFingerScaleStart;
  GestureScaleUpdateCallback? onThreeFingerScaleUpdate;
  GestureScaleEndCallback? onThreeFingerScaleEnd;

  var _currentState = GestureState.none;
  Timer? _debounceTimer;
  ScaleUpdateDetails? _pendingOneFingerDetails;
  bool _deferOneFingerAfterMultiEnd = false;

  void _init() {
    debugPrint("CustomTouchGestureRecognizer init");
    onUpdate = _handleUpdate;
    onEnd = (d) {
      debugPrint("ScaleGestureRecognizer onEnd");
      final shouldDeferOneFinger =
          _isMultiFingerState(_currentState) || _deferOneFingerAfterMultiEnd;
      _cancelPendingOneFingerStart();
      _exitCurrentState(d);
      if (shouldDeferOneFinger && d.pointerCount > 0) {
        if (d.pointerCount > 3) {
          _deferOneFingerAfterMultiEnd = true;
        } else {
          _armOneFingerDelayWindow();
        }
      }
    };
  }

  void _handleUpdate(ScaleUpdateDetails details) {
    switch (details.pointerCount) {
      case 1:
        _handleOneFingerUpdate(details);
        return;
      case 2:
      case 3:
        _handleMultiFingerUpdate(details);
        return;
      default:
        final shouldDeferOneFinger = details.pointerCount > 3 ||
            _isMultiFingerState(_currentState) ||
            _deferOneFingerAfterMultiEnd;
        _debounceTimer?.cancel();
        _debounceTimer = null;
        _pendingOneFingerDetails = null;
        _exitCurrentState(ScaleEndDetails(pointerCount: details.pointerCount));
        _deferOneFingerAfterMultiEnd = shouldDeferOneFinger;
        return;
    }
  }

  void _handleOneFingerUpdate(ScaleUpdateDetails details) {
    if (_currentState == GestureState.oneFingerPan) {
      onOneFingerPanUpdate?.call(_getDragUpdateDetails(details));
      return;
    }

    if (_isMultiFingerState(_currentState)) {
      _exitCurrentState(ScaleEndDetails(pointerCount: details.pointerCount));
      _scheduleOneFingerStart(details);
      return;
    }

    if (_deferOneFingerAfterMultiEnd) {
      _scheduleOneFingerStart(details);
      return;
    }

    if (_pendingOneFingerDetails != null) {
      _pendingOneFingerDetails = details;
      return;
    }

    _enterOneFingerState(details);
    onOneFingerPanUpdate?.call(_getDragUpdateDetails(details));
  }

  void _handleMultiFingerUpdate(ScaleUpdateDetails details) {
    _cancelPendingOneFingerStart();
    final nextState = _stateForPointerCount(details.pointerCount);
    if (_currentState != nextState) {
      _exitCurrentState(ScaleEndDetails(pointerCount: details.pointerCount));
      _enterMultiFingerState(nextState, details);
    }
    _dispatchMultiFingerUpdate(details);
  }

  GestureState _stateForPointerCount(int pointerCount) {
    if (multiFingerGestureMode ==
        MultiFingerGestureMode.twoFingerScrollThreeFingerScale) {
      return pointerCount == 2
          ? GestureState.twoFingerScroll
          : GestureState.threeFingerScale;
    }
    return pointerCount == 2
        ? GestureState.twoFingerScale
        : GestureState.threeFingerVerticalDrag;
  }

  void _enterOneFingerState(ScaleUpdateDetails details) {
    _currentState = GestureState.oneFingerPan;
    onOneFingerPanStart?.call(DragStartDetails(
      localPosition: details.localFocalPoint,
      globalPosition: details.focalPoint,
    ));
  }

  void _enterMultiFingerState(GestureState state, ScaleUpdateDetails details) {
    _currentState = state;
    final startDetails = ScaleStartDetails(
      localFocalPoint: details.localFocalPoint,
      focalPoint: details.focalPoint,
      pointerCount: details.pointerCount,
      sourceTimeStamp: details.sourceTimeStamp,
    );
    switch (state) {
      case GestureState.twoFingerScale:
        onTwoFingerScaleStart?.call(startDetails);
        break;
      case GestureState.threeFingerVerticalDrag:
        onThreeFingerVerticalDragStart?.call(DragStartDetails(
          localPosition: details.localFocalPoint,
          globalPosition: details.focalPoint,
        ));
        break;
      case GestureState.twoFingerScroll:
        onTwoFingerScrollStart?.call(startDetails);
        break;
      case GestureState.threeFingerScale:
        onThreeFingerScaleStart?.call(startDetails);
        break;
      default:
        break;
    }
  }

  void _dispatchMultiFingerUpdate(ScaleUpdateDetails details) {
    switch (_currentState) {
      case GestureState.twoFingerScale:
        onTwoFingerScaleUpdate?.call(details);
        break;
      case GestureState.threeFingerVerticalDrag:
        onThreeFingerVerticalDragUpdate?.call(_getDragUpdateDetails(details));
        break;
      case GestureState.twoFingerScroll:
        onTwoFingerScrollUpdate?.call(details);
        break;
      case GestureState.threeFingerScale:
        onThreeFingerScaleUpdate?.call(details);
        break;
      default:
        break;
    }
  }

  void _exitCurrentState(ScaleEndDetails details,
      {bool cancelOneFinger = false}) {
    final previousState = _currentState;
    _currentState = GestureState.none;
    switch (previousState) {
      case GestureState.oneFingerPan:
        if (cancelOneFinger) {
          onOneFingerPanCancel?.call();
        } else {
          onOneFingerPanEnd?.call(_getDragEndDetails(details));
        }
        break;
      case GestureState.twoFingerScale:
        onTwoFingerScaleEnd?.call(details);
        break;
      case GestureState.threeFingerVerticalDrag:
        onThreeFingerVerticalDragEnd?.call(_getDragEndDetails(details));
        break;
      case GestureState.twoFingerScroll:
        onTwoFingerScrollEnd?.call(details);
        break;
      case GestureState.threeFingerScale:
        onThreeFingerScaleEnd?.call(details);
        break;
      case GestureState.none:
        break;
    }
  }

  void _scheduleOneFingerStart(ScaleUpdateDetails details) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _deferOneFingerAfterMultiEnd = false;
    _pendingOneFingerDetails = details;
    _debounceTimer = Timer(_multiToOneFingerDelay, () {
      _debounceTimer = null;
      final pendingDetails = _pendingOneFingerDetails;
      _pendingOneFingerDetails = null;
      if (_currentState == GestureState.none && pendingDetails != null) {
        _enterOneFingerState(pendingDetails);
      }
    });
  }

  void _armOneFingerDelayWindow() {
    _deferOneFingerAfterMultiEnd = true;
    _debounceTimer = Timer(_multiToOneFingerDelay, () {
      _debounceTimer = null;
      _deferOneFingerAfterMultiEnd = false;
    });
  }

  void _cancelPendingOneFingerStart() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingOneFingerDetails = null;
    _deferOneFingerAfterMultiEnd = false;
  }

  bool _isMultiFingerState(GestureState state) {
    return state == GestureState.twoFingerScale ||
        state == GestureState.threeFingerVerticalDrag ||
        state == GestureState.twoFingerScroll ||
        state == GestureState.threeFingerScale;
  }

  DragUpdateDetails _getDragUpdateDetails(ScaleUpdateDetails d) =>
      DragUpdateDetails(
          globalPosition: d.focalPoint,
          localPosition: d.localFocalPoint,
          delta: d.focalPointDelta);

  DragEndDetails _getDragEndDetails(ScaleEndDetails d) =>
      DragEndDetails(velocity: d.velocity);

  @override
  void rejectGesture(int pointer) {
    _cancelPendingOneFingerStart();
    _exitCurrentState(ScaleEndDetails(), cancelOneFinger: true);
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    _cancelPendingOneFingerStart();
    _currentState = GestureState.none;
    super.dispose();
  }
}

class HoldTapMoveGestureRecognizer extends GestureRecognizer {
  HoldTapMoveGestureRecognizer({
    Object? debugOwner,
    Set<PointerDeviceKind>? supportedDevices,
  }) : super(
          debugOwner: debugOwner,
          supportedDevices: supportedDevices,
        );

  GestureDragStartCallback? onHoldDragStart;
  GestureDragUpdateCallback? onHoldDragUpdate;
  GestureDragDownCallback? onHoldDragDown;
  GestureDragCancelCallback? onHoldDragCancel;
  GestureDragEndCallback? onHoldDragEnd;

  bool _isStart = false;

  Timer? _firstTapUpTimer;
  Timer? _secondTapDownTimer;
  _TapTracker? _firstTap;
  _TapTracker? _secondTap;

  PointerDownEvent? _lastPointerDownEvent;

  final Map<int, _TapTracker> _trackers = <int, _TapTracker>{};

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (_firstTap == null) {
      switch (event.buttons) {
        case kPrimaryButton:
          if (onHoldDragStart == null &&
              onHoldDragUpdate == null &&
              onHoldDragCancel == null &&
              onHoldDragEnd == null) {
            return false;
          }
          break;
        default:
          return false;
      }
    }
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_firstTap != null) {
      if (!_firstTap!.isWithinGlobalTolerance(event, kDoubleTapSlop)) {
        // Ignore out-of-bounds second taps.
        return;
      } else if (!_firstTap!.hasElapsedMinTime() ||
          !_firstTap!.hasSameButton(event)) {
        // Restart when the second tap is too close to the first (touch screens
        // often detect touches intermittently), or when buttons mismatch.
        _reset();
        return _trackTap(event);
      } else if (onHoldDragDown != null) {
        invokeCallback<void>(
            'onHoldDragDown',
            () => onHoldDragDown!(DragDownDetails(
                globalPosition: event.position,
                localPosition: event.localPosition)));
      }
    }
    _trackTap(event);
  }

  void _trackTap(PointerDownEvent event) {
    _stopFirstTapUpTimer();
    _stopSecondTapDownTimer();
    final _TapTracker tracker = _TapTracker(
      event: event,
      entry: GestureBinding.instance.gestureArena.add(event.pointer, this),
      doubleTapMinTime: kDoubleTapMinTime,
      gestureSettings: gestureSettings,
    );
    _trackers[event.pointer] = tracker;
    _lastPointerDownEvent = event;
    tracker.startTrackingPointer(_handleEvent, event.transform);
  }

  void _handleEvent(PointerEvent event) {
    final _TapTracker tracker = _trackers[event.pointer]!;
    if (event is PointerUpEvent) {
      if (_firstTap == null && _secondTap == null) {
        _registerFirstTap(tracker);
      } else if (_secondTap != null) {
        if (event.pointer == _secondTap!.pointer) {
          if (onHoldDragEnd != null) {
            onHoldDragEnd!(DragEndDetails());
            _secondTap = null;
            _isStart = false;
          }
        }
      } else {
        _reject(tracker);
      }
    } else if (event is PointerDownEvent) {
      if (_firstTap != null && _secondTap == null) {
        _registerSecondTap(tracker);
      }
    } else if (event is PointerMoveEvent) {
      if (!tracker.isWithinGlobalTolerance(event, kDoubleTapTouchSlop)) {
        if (_firstTap != null && _firstTap!.pointer == event.pointer) {
          // first tap move
          _reject(tracker);
        } else if (_secondTap != null && _secondTap!.pointer == event.pointer) {
          // debugPrint("_secondTap move");
          // second tap move
          if (!_isStart) {
            _resolve();
          }
          if (onHoldDragUpdate != null) {
            onHoldDragUpdate!(DragUpdateDetails(
                globalPosition: event.position,
                localPosition: event.localPosition,
                delta: event.delta));
          }
        }
      }
    } else if (event is PointerCancelEvent) {
      _reject(tracker);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _TapTracker? tracker = _trackers[pointer];
    // If tracker isn't in the list, check if this is the first tap tracker
    if (tracker == null && _firstTap != null && _firstTap!.pointer == pointer) {
      tracker = _firstTap;
    }
    // If tracker is still null, we rejected ourselves already
    if (tracker != null) {
      _reject(tracker);
    }
  }

  void _resolve() {
    _stopSecondTapDownTimer();
    _firstTap?.entry.resolve(GestureDisposition.accepted);
    _secondTap?.entry.resolve(GestureDisposition.accepted);
    _isStart = true;
    // TODO start details
    if (onHoldDragStart != null) {
      onHoldDragStart!(DragStartDetails(
        kind: _lastPointerDownEvent?.kind,
      ));
    }
  }

  void _reject(_TapTracker tracker) {
    try {
      _checkCancel();
      _isStart = false;
      _trackers.remove(tracker.pointer);
      tracker.entry.resolve(GestureDisposition.rejected);
      _freezeTracker(tracker);
      _reset();
    } catch (e) {
      debugPrint("Failed to _reject:$e");
    }
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  void _reset() {
    _isStart = false;
    // debugPrint("reset");
    _stopFirstTapUpTimer();
    _stopSecondTapDownTimer();
    if (_firstTap != null) {
      if (_trackers.isNotEmpty) {
        _checkCancel();
      }
      // Note, order is important below in order for the resolve -> reject logic
      // to work properly.
      final _TapTracker tracker = _firstTap!;
      _firstTap = null;
      _reject(tracker);
      GestureBinding.instance.gestureArena.release(tracker.pointer);

      if (_secondTap != null) {
        final _TapTracker tracker = _secondTap!;
        _secondTap = null;
        _reject(tracker);
        GestureBinding.instance.gestureArena.release(tracker.pointer);
      }
    }
    _firstTap = null;
    _secondTap = null;
    _clearTrackers();
  }

  void _registerFirstTap(_TapTracker tracker) {
    _startFirstTapUpTimer();
    GestureBinding.instance.gestureArena.hold(tracker.pointer);
    // Note, order is important below in order for the clear -> reject logic to
    // work properly.
    _freezeTracker(tracker);
    _trackers.remove(tracker.pointer);
    _firstTap = tracker;
  }

  void _registerSecondTap(_TapTracker tracker) {
    if (_firstTap != null) {
      _stopFirstTapUpTimer();
      _freezeTracker(_firstTap!);
      _firstTap = null;
    }

    _startSecondTapDownTimer();
    GestureBinding.instance.gestureArena.hold(tracker.pointer);

    _secondTap = tracker;

    // TODO
  }

  void _clearTrackers() {
    _trackers.values.toList().forEach(_reject);
    assert(_trackers.isEmpty);
  }

  void _freezeTracker(_TapTracker tracker) {
    tracker.stopTrackingPointer(_handleEvent);
  }

  void _startFirstTapUpTimer() {
    _firstTapUpTimer ??= Timer(kDoubleTapTimeout, _reset);
  }

  void _startSecondTapDownTimer() {
    _secondTapDownTimer ??= Timer(kDoubleTapTimeout, _resolve);
  }

  void _stopFirstTapUpTimer() {
    if (_firstTapUpTimer != null) {
      _firstTapUpTimer!.cancel();
      _firstTapUpTimer = null;
    }
  }

  void _stopSecondTapDownTimer() {
    if (_secondTapDownTimer != null) {
      _secondTapDownTimer!.cancel();
      _secondTapDownTimer = null;
    }
  }

  void _checkCancel() {
    if (onHoldDragCancel != null) {
      invokeCallback<void>('onHoldDragCancel', onHoldDragCancel!);
    }
  }

  @override
  String get debugDescription => 'double tap';
}

class DoubleFinerTapGestureRecognizer extends GestureRecognizer {
  DoubleFinerTapGestureRecognizer({
    Object? debugOwner,
    Set<PointerDeviceKind>? supportedDevices,
  }) : super(
          debugOwner: debugOwner,
          supportedDevices: supportedDevices,
        );

  GestureTapDownCallback? onDoubleFinerTapDown;
  GestureTapDownCallback? onDoubleFinerTap;
  GestureTapCancelCallback? onDoubleFinerTapCancel;

  Timer? _firstTapTimer;
  _TapTracker? _firstTap;

  PointerDownEvent? _lastPointerDownEvent;

  var _isStart = false;

  final Set<int> _upTap = {};

  final Map<int, _TapTracker> _trackers = <int, _TapTracker>{};

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (_firstTap == null) {
      switch (event.buttons) {
        case kPrimaryButton:
          if (onDoubleFinerTapDown == null &&
              onDoubleFinerTap == null &&
              onDoubleFinerTapCancel == null) {
            return false;
          }
          break;
        default:
          return false;
      }
    }
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    debugPrint("addAllowedPointer");
    if (_isStart) {
      // second
      if (onDoubleFinerTapDown != null) {
        final TapDownDetails details = TapDownDetails(
          globalPosition: event.position,
          localPosition: event.localPosition,
          kind: getKindForPointer(event.pointer),
        );
        invokeCallback<void>(
            'onDoubleFinerTapDown', () => onDoubleFinerTapDown!(details));
      }
    } else {
      // first tap
      _isStart = true;
      _lastPointerDownEvent = event;
      _startFirstTapDownTimer();
    }
    _trackTap(event);
  }

  void _trackTap(PointerDownEvent event) {
    final _TapTracker tracker = _TapTracker(
      event: event,
      entry: GestureBinding.instance.gestureArena.add(event.pointer, this),
      doubleTapMinTime: kDoubleTapMinTime,
      gestureSettings: gestureSettings,
    );
    _trackers[event.pointer] = tracker;
    // debugPrint("_trackers:$_trackers");
    tracker.startTrackingPointer(_handleEvent, event.transform);

    _registerTap(tracker);
  }

  void _handleEvent(PointerEvent event) {
    final _TapTracker tracker = _trackers[event.pointer]!;
    if (event is PointerUpEvent) {
      debugPrint("PointerUpEvent");
      _upTap.add(tracker.pointer);
    } else if (event is PointerMoveEvent) {
      if (!tracker.isWithinGlobalTolerance(event, kDoubleTapTouchSlop)) {
        _reject(tracker);
      }
    } else if (event is PointerCancelEvent) {
      _reject(tracker);
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _TapTracker? tracker = _trackers[pointer];
    // If tracker isn't in the list, check if this is the first tap tracker
    if (tracker == null && _firstTap != null && _firstTap!.pointer == pointer) {
      tracker = _firstTap;
    }
    // If tracker is still null, we rejected ourselves already
    if (tracker != null) {
      _reject(tracker);
    }
  }

  void _reject(_TapTracker tracker) {
    _trackers.remove(tracker.pointer);
    tracker.entry.resolve(GestureDisposition.rejected);
    _freezeTracker(tracker);
    if (_firstTap != null) {
      if (tracker == _firstTap) {
        _reset();
      } else {
        _checkCancel();
        if (_trackers.isEmpty) {
          _reset();
        }
      }
    }
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  void _reset() {
    _stopFirstTapUpTimer();
    _firstTap = null;
    _clearTrackers();
  }

  void _registerTap(_TapTracker tracker) {
    GestureBinding.instance.gestureArena.hold(tracker.pointer);
    // Note, order is important below in order for the clear -> reject logic to
    // work properly.
  }

  void _clearTrackers() {
    _trackers.values.toList().forEach(_reject);
    assert(_trackers.isEmpty);
  }

  void _freezeTracker(_TapTracker tracker) {
    tracker.stopTrackingPointer(_handleEvent);
  }

  void _startFirstTapDownTimer() {
    _firstTapTimer ??= Timer(kDoubleTapTimeout, _timeoutCheck);
  }

  void _stopFirstTapUpTimer() {
    if (_firstTapTimer != null) {
      _firstTapTimer!.cancel();
      _firstTapTimer = null;
    }
  }

  void _timeoutCheck() {
    _isStart = false;
    if (_upTap.length == 2) {
      _resolve();
    } else {
      _reset();
    }
    _upTap.clear();
  }

  void _resolve() {
    // TODO tap down details
    if (onDoubleFinerTap != null) {
      onDoubleFinerTap!(TapDownDetails(
        kind: _lastPointerDownEvent?.kind,
      ));
    }
    _trackers.forEach((key, value) {
      value.entry.resolve(GestureDisposition.accepted);
    });
    _reset();
  }

  void _checkCancel() {
    if (onDoubleFinerTapCancel != null) {
      invokeCallback<void>('onHoldDragCancel', onDoubleFinerTapCancel!);
    }
  }

  @override
  String get debugDescription => 'double tap';
}

/// TapTracker helps track individual tap sequences as part of a
/// larger gesture.
class _TapTracker {
  _TapTracker({
    required PointerDownEvent event,
    required this.entry,
    required Duration doubleTapMinTime,
    required this.gestureSettings,
  })  : pointer = event.pointer,
        _initialGlobalPosition = event.position,
        initialButtons = event.buttons,
        _doubleTapMinTimeCountdown =
            _CountdownZoned(duration: doubleTapMinTime);

  final DeviceGestureSettings? gestureSettings;
  final int pointer;
  final GestureArenaEntry entry;
  final Offset _initialGlobalPosition;
  final int initialButtons;
  final _CountdownZoned _doubleTapMinTimeCountdown;

  bool _isTrackingPointer = false;

  void startTrackingPointer(PointerRoute route, Matrix4? transform) {
    if (!_isTrackingPointer) {
      _isTrackingPointer = true;
      GestureBinding.instance.pointerRouter.addRoute(pointer, route, transform);
    }
  }

  void stopTrackingPointer(PointerRoute route) {
    if (_isTrackingPointer) {
      _isTrackingPointer = false;
      GestureBinding.instance.pointerRouter.removeRoute(pointer, route);
    }
  }

  bool isWithinGlobalTolerance(PointerEvent event, double tolerance) {
    final Offset offset = event.position - _initialGlobalPosition;
    return offset.distance <= tolerance;
  }

  bool hasElapsedMinTime() {
    return _doubleTapMinTimeCountdown.timeout;
  }

  bool hasSameButton(PointerDownEvent event) {
    return event.buttons == initialButtons;
  }
}

/// CountdownZoned tracks whether the specified duration has elapsed since
/// creation, honoring [Zone].
class _CountdownZoned {
  _CountdownZoned({required Duration duration}) {
    Timer(duration, _onTimeout);
  }

  bool _timeout = false;

  bool get timeout => _timeout;

  void _onTimeout() {
    _timeout = true;
  }
}

RawGestureDetector getMixinGestureDetector({
  Widget? child,
  MultiFingerGestureMode multiFingerGestureMode = MultiFingerGestureMode.legacy,
  GestureTapUpCallback? onTapUp,
  GestureTapDownCallback? onDoubleTapDown,
  GestureDoubleTapCallback? onDoubleTap,
  GestureLongPressDownCallback? onLongPressDown,
  GestureLongPressCallback? onLongPress,
  GestureDragStartCallback? onHoldDragStart,
  GestureDragUpdateCallback? onHoldDragUpdate,
  GestureDragCancelCallback? onHoldDragCancel,
  GestureDragEndCallback? onHoldDragEnd,
  GestureTapDownCallback? onDoubleFinerTap,
  GestureDragStartCallback? onOneFingerPanStart,
  GestureDragUpdateCallback? onOneFingerPanUpdate,
  GestureDragEndCallback? onOneFingerPanEnd,
  GestureDragCancelCallback? onOneFingerPanCancel,
  GestureScaleStartCallback? onTwoFingerScaleStart,
  GestureScaleUpdateCallback? onTwoFingerScaleUpdate,
  GestureScaleEndCallback? onTwoFingerScaleEnd,
  GestureDragStartCallback? onThreeFingerVerticalDragStart,
  GestureDragUpdateCallback? onThreeFingerVerticalDragUpdate,
  GestureDragEndCallback? onThreeFingerVerticalDragEnd,
  GestureScaleStartCallback? onTwoFingerScrollStart,
  GestureScaleUpdateCallback? onTwoFingerScrollUpdate,
  GestureScaleEndCallback? onTwoFingerScrollEnd,
  GestureScaleStartCallback? onThreeFingerScaleStart,
  GestureScaleUpdateCallback? onThreeFingerScaleUpdate,
  GestureScaleEndCallback? onThreeFingerScaleEnd,
}) {
  return RawGestureDetector(
      child: child,
      gestures: <Type, GestureRecognizerFactory>{
        // Official
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(), (instance) {
          instance.onTapUp = onTapUp;
        }),
        DoubleTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
                () => DoubleTapGestureRecognizer(), (instance) {
          instance
            ..onDoubleTapDown = onDoubleTapDown
            ..onDoubleTap = onDoubleTap;
        }),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(), (instance) {
          instance
            ..onLongPressDown = onLongPressDown
            ..onLongPress = onLongPress;
        }),
        // Customized
        HoldTapMoveGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HoldTapMoveGestureRecognizer>(
                () => HoldTapMoveGestureRecognizer(),
                (instance) => instance
                  ..onHoldDragStart = onHoldDragStart
                  ..onHoldDragUpdate = onHoldDragUpdate
                  ..onHoldDragCancel = onHoldDragCancel
                  ..onHoldDragEnd = onHoldDragEnd),
        DoubleFinerTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                DoubleFinerTapGestureRecognizer>(
            () => DoubleFinerTapGestureRecognizer(), (instance) {
          instance.onDoubleFinerTap = onDoubleFinerTap;
        }),
        CustomTouchGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<CustomTouchGestureRecognizer>(
                () => CustomTouchGestureRecognizer(), (instance) {
          instance
            ..multiFingerGestureMode = multiFingerGestureMode
            ..onOneFingerPanStart = onOneFingerPanStart
            ..onOneFingerPanUpdate = onOneFingerPanUpdate
            ..onOneFingerPanEnd = onOneFingerPanEnd
            ..onOneFingerPanCancel = onOneFingerPanCancel
            ..onTwoFingerScaleStart = onTwoFingerScaleStart
            ..onTwoFingerScaleUpdate = onTwoFingerScaleUpdate
            ..onTwoFingerScaleEnd = onTwoFingerScaleEnd
            ..onThreeFingerVerticalDragStart = onThreeFingerVerticalDragStart
            ..onThreeFingerVerticalDragUpdate = onThreeFingerVerticalDragUpdate
            ..onThreeFingerVerticalDragEnd = onThreeFingerVerticalDragEnd
            ..onTwoFingerScrollStart = onTwoFingerScrollStart
            ..onTwoFingerScrollUpdate = onTwoFingerScrollUpdate
            ..onTwoFingerScrollEnd = onTwoFingerScrollEnd
            ..onThreeFingerScaleStart = onThreeFingerScaleStart
            ..onThreeFingerScaleUpdate = onThreeFingerScaleUpdate
            ..onThreeFingerScaleEnd = onThreeFingerScaleEnd;
        }),
      });
}
