import 'package:flutter/material.dart';

/// Trang mở từ nút ở mép trái (menu ☰): trượt vào từ TRÁI sang phải, giống ngăn kéo.
///
/// Màn bên dưới đứng yên (không bị đẩy sang trái như trang thường), vuốt từ phải sang trái
/// hoặc bấm nút đóng để thu về bên trái.
class LeftDrawerRoute<T> extends PageRoute<T> {
  LeftDrawerRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  AnimationController get _dragController => controller!;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 280);

  // Trong lúc trượt màn dưới vẫn hiện; mở xong thì ẩn hẳn để không phải vẽ lại bản đồ phía sau.
  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  // Không để màn bên dưới chạy hiệu ứng "bị đẩy sang trái" của trang thường.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => nextRoute is PageRoute && nextRoute is! LeftDrawerRoute;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = Tween(begin: const Offset(-1, 0), end: Offset.zero).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    // Khi mở tiếp một trang con từ menu, menu lùi nhẹ sang trái như trang thường.
    final behind = Tween(begin: Offset.zero, end: const Offset(-0.3, 0))
        .animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic));
    return SlideTransition(
      position: behind,
      child: SlideTransition(
        position: slide,
        child: _SwipeToClose(route: this, child: child),
      ),
    );
  }
}

/// Vuốt sang trái để đóng, ngón tay kéo trang theo.
class _SwipeToClose extends StatefulWidget {
  const _SwipeToClose({required this.route, required this.child});
  final LeftDrawerRoute<dynamic> route;
  final Widget child;

  @override
  State<_SwipeToClose> createState() => _SwipeToCloseState();
}

class _SwipeToCloseState extends State<_SwipeToClose> {
  bool _dragging = false;

  AnimationController get _controller => widget.route._dragController;

  void _start(DragStartDetails _) {
    if (widget.route.isCurrent && !widget.route.navigator!.userGestureInProgress) {
      _dragging = true;
      widget.route.navigator!.didStartUserGesture();
    }
  }

  void _update(DragUpdateDetails d) {
    if (!_dragging) return;
    // Chỉ theo hướng đóng (sang trái); kéo sang phải thì giữ nguyên.
    _controller.value = (_controller.value + d.primaryDelta! / context.size!.width).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final v = d.primaryVelocity ?? 0;
    final close = v < -500 || (v <= 500 && _controller.value < 0.6);
    final nav = widget.route.navigator!;
    if (close) {
      nav.pop();
    } else {
      _controller.forward();
    }
    nav.didStopUserGesture();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _start,
        onHorizontalDragUpdate: _update,
        onHorizontalDragEnd: _end,
        onHorizontalDragCancel: () => _end(DragEndDetails()),
        child: widget.child,
      );
}
