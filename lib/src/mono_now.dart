class MonotonicNow {
  final DateTime _startTime = DateTime.now().toUtc();
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Возвращает время, которым должно быть датировано событие, если оно
  /// произошло "прямо сейчас". В отличие от `DateTime.now()`, тут мы полагаемся
  /// на [Stopwatch] и поэтому надеемся на монотонное возрастание.
  DateTime now() {
    return this._startTime.add(this._stopwatch.elapsed);
  }
}

final monoTime = MonotonicNow();