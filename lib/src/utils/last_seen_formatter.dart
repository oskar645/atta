String formatLastSeen(
  DateTime? lastSeenAt,
  bool isOnline, {
  DateTime? now,
}) {
  if (isOnline) return 'в сети';
  if (lastSeenAt == null) return '';

  final localLastSeen = lastSeenAt.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final lastSeenDay = DateTime(
    localLastSeen.year,
    localLastSeen.month,
    localLastSeen.day,
  );
  final time =
      '${_twoDigits(localLastSeen.hour)}:${_twoDigits(localLastSeen.minute)}';

  final dayDiff = today.difference(lastSeenDay).inDays;
  if (dayDiff == 0) {
    return 'был(а) в сети сегодня в $time';
  }
  if (dayDiff == 1) {
    return 'был(а) в сети вчера в $time';
  }

  final month = _ruMonths[localLastSeen.month - 1];
  final year =
      localLastSeen.year == localNow.year ? '' : ' ${localLastSeen.year} г.';
  return 'был(а) в сети ${localLastSeen.day} $month$year в $time';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

const _ruMonths = <String>[
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
