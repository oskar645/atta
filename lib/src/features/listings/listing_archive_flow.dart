import 'package:atta/src/services/listings_service.dart';
import 'package:flutter/material.dart';

class ListingArchiveDecision {
  const ListingArchiveDecision({
    required this.status,
    required this.note,
    required this.successMessage,
  });

  final String status;
  final String note;
  final String successMessage;
}

const soldListingArchiveDecision = ListingArchiveDecision(
  status: 'sold',
  note: 'Продано владельцем.',
  successMessage: 'Объявление отмечено как проданное',
);

const archivedListingArchiveDecision = ListingArchiveDecision(
  status: 'archived',
  note: 'Снято владельцем с публикации.',
  successMessage: 'Объявление снято с публикации',
);

Future<ListingArchiveDecision?> showListingArchiveConfirmation(
  BuildContext context,
) {
  return showModalBottomSheet<ListingArchiveDecision>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Снять объявление?',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Вы продали товар или хотите временно снять объявление с публикации?',
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(
                  soldListingArchiveDecision,
                ),
                child: const Text('Да, продано'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(sheetContext).pop(
                  archivedListingArchiveDecision,
                ),
                child: const Text('Снять без продажи'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Отмена'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> runListingArchiveFlow(
  BuildContext context, {
  required String listingId,
  required ListingsService listingsService,
  VoidCallback? onUpdated,
}) async {
  final decision = await showListingArchiveConfirmation(context);
  if (decision == null) {
    return false;
  }

  try {
    await listingsService.archiveListing(
      listingId: listingId,
      status: decision.status,
      note: decision.note,
    );
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(decision.successMessage)),
    );
    onUpdated?.call();
    return true;
  } catch (_) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось обновить объявление')),
    );
    return false;
  }
}
