#!/usr/bin/env ts-node
import 'dotenv/config';

import { PrismaClient } from '@prisma/client';

import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../common/phone';

const prisma = new PrismaClient();

async function main() {
  const rawPhone = process.argv[2]?.trim() ?? '';
  if (!rawPhone) {
    throw new Error('Phone number is required. Example: npm run admin -- 79288888645');
  }

  const normalizedPhone = normalizeRussianPhone(rawPhone);
  validateRussianPhoneOrThrow(normalizedPhone);

  const user = await prisma.user.findUnique({
    where: {
      phone: normalizedPhone,
    },
    select: {
      id: true,
      phone: true,
      displayName: true,
      adminProfile: {
        select: {
          isAdmin: true,
        },
      },
    },
  });

  if (!user) {
    throw new Error('User with this phone number was not found');
  }

  await prisma.adminUser.upsert({
    where: {
      userId: user.id,
    },
    update: {
      isAdmin: true,
      role: 'admin',
    },
    create: {
      userId: user.id,
      isAdmin: true,
      role: 'admin',
      permissions: {},
    },
  });

  console.log(
    `Admin access granted for user ${user.displayName || user.id} (${normalizedPhone})`,
  );
}

main()
  .catch((error: unknown) => {
    const message =
      error instanceof Error ? error.message : 'Unknown error while granting admin access';
    console.error(message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
