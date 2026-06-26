#!/usr/bin/env ts-node
import 'dotenv/config';

import { ListingStatus, PrismaClient, UserStatus } from '@prisma/client';

import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../common/phone';
import { parseAdminPhoneNumbers } from '../config/env';

const prisma = new PrismaClient();

const DEFAULT_ADMIN_PHONES = ['79288888645', '79306939954'] as const;
const DEFAULT_USER_PHONE = '79859257340';
const DEFAULT_TEST_PHONE = '79304262338';

type Flags = {
  apply: boolean;
  phone: string;
};

function parseFlags(argv: string[]): Flags {
  let apply = false;
  let phone = DEFAULT_TEST_PHONE;

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index]?.trim() ?? '';
    if (value === '--apply') {
      apply = true;
      continue;
    }
    if (value === '--phone') {
      phone = argv[index + 1]?.trim() ?? phone;
      index += 1;
    }
  }

  const normalizedPhone = normalizeRussianPhone(phone);
  validateRussianPhoneOrThrow(normalizedPhone);
  return {
    apply,
    phone: normalizedPhone,
  };
}

async function main() {
  const flags = parseFlags(process.argv.slice(2));
  const expectedAdminPhones = DEFAULT_ADMIN_PHONES.map(normalizeRussianPhone);
  const envAdminPhones = parseAdminPhoneNumbers();

  console.log('ATTA admin phones (expected):', expectedAdminPhones.join(','));
  console.log('ATTA admin phones (.env):', envAdminPhones.join(',') || '(empty)');
  console.log('ATTA regular user phone (expected user):', DEFAULT_USER_PHONE);
  console.log('ATTA target test phone:', flags.phone);
  console.log('Mode:', flags.apply ? 'APPLY' : 'DRY-RUN');

  const phonesToInspect = [
    ...new Set([...expectedAdminPhones, DEFAULT_USER_PHONE, flags.phone]),
  ];

  const users = await prisma.user.findMany({
    where: {
      phone: {
        in: phonesToInspect,
      },
    },
    include: {
      adminProfile: true,
      listings: {
        orderBy: {
          createdAt: 'desc',
        },
        select: {
          id: true,
          title: true,
          status: true,
          publishedAt: true,
          archivedAt: true,
          deletedAt: true,
          createdAt: true,
        },
      },
    },
    orderBy: {
      createdAt: 'desc',
    },
  });

  console.log('\nUsers snapshot:');
  for (const user of users) {
    console.log(
      JSON.stringify(
        {
          id: user.id,
          phone: user.phone,
          displayName: user.displayName,
          name: user.name,
          status: user.status,
          deletedAt: user.deletedAt?.toISOString() ?? null,
          blockedAt: user.blockedAt?.toISOString() ?? null,
          isAdmin: user.adminProfile?.isAdmin === true,
          adminRole: user.adminProfile?.role ?? null,
          listings: user.listings.map((listing) => ({
            id: listing.id,
            title: listing.title,
            status: listing.status,
            publishedAt: listing.publishedAt?.toISOString() ?? null,
            archivedAt: listing.archivedAt?.toISOString() ?? null,
            deletedAt: listing.deletedAt?.toISOString() ?? null,
          })),
        },
        null,
        2,
      ),
    );
  }

  const targetUser = users.find((user) => user.phone === flags.phone);
  if (!targetUser) {
    console.log('\nTarget user not found. No cleanup needed.');
    return;
  }

  const targetListingIds = targetUser.listings.map((listing) => listing.id);
  const targetListingTitles = targetUser.listings.map((listing) => listing.title);

  console.log('\nPlanned cleanup target:');
  console.log(
    JSON.stringify(
      {
        userId: targetUser.id,
        phone: targetUser.phone,
        displayName: targetUser.displayName,
        statusBefore: targetUser.status,
        listingTitles: targetListingTitles,
      },
      null,
      2,
    ),
  );

  if (!flags.apply) {
    console.log('\nDry-run only. No database changes were made.');
    console.log(
      'To apply safe cleanup run: npm run data:audit:test-user -- --phone 79304262338 --apply',
    );
    return;
  }

  const now = new Date();
  const reason = 'Soft-hidden by audit-test-data.ts to remove moderation test data from public feed.';

  await prisma.$transaction(async (tx) => {
    if (targetListingIds.length > 0) {
      await tx.listing.updateMany({
        where: {
          id: {
            in: targetListingIds,
          },
          deletedAt: null,
        },
        data: {
          status: ListingStatus.ARCHIVED,
          archivedAt: now,
          publishedAt: null,
          moderationNote: reason,
          rejectionReason: reason,
        },
      });
    }

    await tx.user.update({
      where: {
        id: targetUser.id,
      },
      data: {
        status: UserStatus.BLOCKED,
        blockedAt: now,
        blockReason: reason,
      },
    });
  });

  console.log('\nCleanup applied.');
  console.log(
    JSON.stringify(
      {
        userId: targetUser.id,
        userStatusAfter: UserStatus.BLOCKED,
        archivedListings: targetListingTitles,
      },
      null,
      2,
    ),
  );
}

main()
  .catch((error: unknown) => {
    const message =
      error instanceof Error ? error.message : 'Unknown error while auditing test data';
    console.error(message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
