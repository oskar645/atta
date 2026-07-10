#!/usr/bin/env ts-node
import 'dotenv/config';

import { PrismaClient } from '@prisma/client';

import { normalizeRussianPhone, validateRussianPhoneOrThrow } from '../common/phone';
import { WalletService } from '../modules/wallet/wallet.service';

const prisma = new PrismaClient();
const walletService = new WalletService(prisma as never);

const ADMIN_PHONES = ['79288888645', '79306939954'] as const;
const BONUS_AMOUNT = 5000;
const BONUS_REFERENCE = 'ADMIN_TEST_BONUS_5000_2026_07';
const BONUS_DESCRIPTION = 'Тестовые бонусы от администрации ATTA';

type AdminLookupResult = {
  found: boolean;
  normalizedPhone: string;
  displayLabel: string;
  userId?: string;
  isAdmin?: boolean;
};

function buildPhoneCandidates(rawPhone: string) {
  const digits = rawPhone.replace(/\D/g, '');
  const normalizedPhone = normalizeRussianPhone(rawPhone);
  validateRussianPhoneOrThrow(normalizedPhone);
  const localNumber = normalizedPhone.slice(1);

  return {
    normalizedPhone,
    candidates: Array.from(
      new Set([
        rawPhone.trim(),
        digits,
        normalizedPhone,
        `+${normalizedPhone}`,
        `8${localNumber}`,
        `+7 ${localNumber.slice(0, 3)} ${localNumber.slice(3, 6)} ${localNumber.slice(6, 8)} ${localNumber.slice(8, 10)}`,
      ]).values(),
    ).filter((value) => value.trim().length > 0),
  };
}

async function findAdminByPhone(rawPhone: string): Promise<AdminLookupResult> {
  const { normalizedPhone, candidates } = buildPhoneCandidates(rawPhone);

  const user = await prisma.user.findFirst({
    where: {
      OR: candidates.map((candidate) => ({
        phone: candidate,
      })),
    },
    select: {
      id: true,
      phone: true,
      displayName: true,
      wallet: {
        select: {
          bonusBalance: true,
        },
      },
      adminProfile: {
        select: {
          isAdmin: true,
        },
      },
    },
  });

  if (!user) {
    return {
      found: false,
      normalizedPhone,
      displayLabel: normalizedPhone,
    };
  }

  return {
    found: true,
    normalizedPhone,
    displayLabel: user.phone ?? normalizedPhone,
    userId: user.id,
    isAdmin: user.adminProfile?.isAdmin === true,
  };
}

async function main() {
  for (const rawPhone of ADMIN_PHONES) {
    const lookup = await findAdminByPhone(rawPhone);

    if (!lookup.found || !lookup.userId) {
      console.log(`Админ ${lookup.normalizedPhone}: не найден.`);
      continue;
    }

    if (lookup.isAdmin !== true) {
      console.log(`Админ ${lookup.displayLabel}: найден, но не является администратором.`);
      continue;
    }

    console.log(`Админ ${lookup.displayLabel}: найден.`);

    const result = await walletService.accrueManualBonusIfNeeded(
      lookup.userId,
      {
        amount: BONUS_AMOUNT,
        reference: BONUS_REFERENCE,
        description: BONUS_DESCRIPTION,
        source: 'admin_test_bonus',
      },
    );

    if (result.applied) {
      console.log(
        `Начислено: ${BONUS_AMOUNT}. Баланс: ${result.wallet.bonusBalance}.`,
      );
      continue;
    }

    console.log(`Уже было начислено. Баланс: ${result.wallet.bonusBalance}.`);
  }
}

main()
  .catch((error: unknown) => {
    const message =
      error instanceof Error
        ? error.message
        : 'Не удалось начислить тестовые бонусы администраторам';
    console.error(message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
