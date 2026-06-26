#!/usr/bin/env ts-node
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
const client_1 = require("@prisma/client");
const phone_1 = require("../common/phone");
const prisma = new client_1.PrismaClient();
async function main() {
    const rawPhone = process.argv[2]?.trim() ?? '';
    if (!rawPhone) {
        throw new Error('Phone number is required. Example: npm run admin -- 79288888645');
    }
    const normalizedPhone = (0, phone_1.normalizeRussianPhone)(rawPhone);
    (0, phone_1.validateRussianPhoneOrThrow)(normalizedPhone);
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
    console.log(`Admin access granted for user ${user.displayName || user.id} (${normalizedPhone})`);
}
main()
    .catch((error) => {
    const message = error instanceof Error ? error.message : 'Unknown error while granting admin access';
    console.error(message);
    process.exitCode = 1;
})
    .finally(async () => {
    await prisma.$disconnect();
});
//# sourceMappingURL=grant-admin.js.map