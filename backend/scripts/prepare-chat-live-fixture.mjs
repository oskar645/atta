#!/usr/bin/env node

const baseUrl = process.env.BACKEND_URL || 'http://5.42.125.179';
const password = process.env.TEST_USER_PASSWORD || 'Test12345';
const phoneA = process.env.TEST_PHONE_A || '79000000001';
const phoneB = process.env.TEST_PHONE_B || '79000000002';
const nameA = process.env.TEST_NAME_A || 'ATTA Test Admin';
const nameB = process.env.TEST_NAME_B || 'ATTA Test Buyer';

function maskToken(value) {
  const token = String(value || '');
  if (token.length <= 12) return '***';
  return `${token.slice(0, 6)}...${token.slice(-4)}`;
}

function authPayload(response) {
  const auth = response?.auth ?? response ?? {};
  return {
    userId: String(auth.user_id || response?.user?.id || response?.userId || ''),
    accessToken: String(auth.access_token || response?.access_token || ''),
    refreshToken: String(auth.refresh_token || response?.refresh_token || ''),
  };
}

async function api(path, { method = 'GET', token, body } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body == null ? undefined : JSON.stringify(body),
  });

  const text = await response.text();
  const data = text.trim() ? JSON.parse(text) : {};
  if (!response.ok) {
    const message =
      data?.message ||
      data?.error ||
      `HTTP ${response.status} ${response.statusText}`;
    throw new Error(`${method} ${path} failed: ${message}`);
  }
  return data;
}

async function ensureVerifiedPhone(phone) {
  console.log(`[fixture] verifying phone ${phone}`);
  await api('/auth/phone/check-registration', {
    method: 'POST',
    body: { phone },
  });
  const start = await api('/auth/phone/start', {
    method: 'POST',
    body: { phone, purpose: 'signup' },
  });
  await api('/auth/phone/check', {
    method: 'POST',
    body: {
      phone,
      checkId: start.checkId,
      purpose: 'signup',
    },
  });
  return start.checkId;
}

async function ensureUser({ phone, displayName }) {
  console.log(`[fixture] ensuring user ${phone}`);
  const registration = await api('/auth/phone/check-registration', {
    method: 'POST',
    body: { phone },
  });

  if (registration.exists === true) {
    console.log(`[fixture] phone ${phone} already exists, logging in`);
    const login = await api('/auth/login-phone', {
      method: 'POST',
      body: { phone, password },
    });
    const auth = authPayload(login);
    return {
      userId: auth.userId,
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      mode: 'login',
    };
  }

  const verificationCheckId = await ensureVerifiedPhone(phone);
  console.log(`[fixture] signing up ${phone}`);
  const signup = await api('/auth/signup-phone', {
    method: 'POST',
    body: {
      phone,
      password,
      displayName,
      verificationCheckId,
    },
  });
  const auth = authPayload(signup);

  return {
    userId: auth.userId,
    accessToken: auth.accessToken,
    refreshToken: auth.refreshToken,
    mode: 'signup',
  };
}

async function ensureListing(accessToken) {
  console.log('[fixture] ensuring approved listing for user A');
  const mine = await api('/listings/my', {
    token: accessToken,
  });
  const existing = (mine.items || []).find(
    (item) =>
      item?.title === 'ATTA Chat Live Test Listing' &&
      item?.status === 'approved',
  );
  if (existing?.id) {
    console.log(`[fixture] reusing listing ${existing.id}`);
    return existing;
  }

  const created = await api('/listings', {
    method: 'POST',
    token: accessToken,
    body: {
      title: 'ATTA Chat Live Test Listing',
      description: 'Temporary listing for Timeweb chat live verification.',
      category: 'Авто',
      subcategory: 'Тест',
      price: 12345,
      city: 'Moscow',
      address: 'ATTA Test Address',
      phone: phoneA,
      phone_hidden: false,
      status: 'approved',
      delivery: { pickup: true },
      location: {
        latitude: 55.7558,
        longitude: 37.6173,
      },
      photo_urls: [],
    },
  });

  return created.listing;
}

async function ensureChat(accessTokenB, listingId, sellerId) {
  console.log('[fixture] ensuring chat for user B');
  const result = await api('/chats', {
    method: 'POST',
    token: accessTokenB,
    body: {
      listingId,
      sellerId,
    },
  });
  return result.chat;
}

async function main() {
  console.log(`[fixture] baseUrl=${baseUrl}`);
  const userA = await ensureUser({ phone: phoneA, displayName: nameA });
  const userB = await ensureUser({ phone: phoneB, displayName: nameB });
  const listing = await ensureListing(userA.accessToken);
  const chat = await ensureChat(userB.accessToken, listing.id, userA.userId);

  console.log('[fixture] userA', {
    userId: userA.userId,
    mode: userA.mode,
    accessToken: maskToken(userA.accessToken),
  });
  console.log('[fixture] userB', {
    userId: userB.userId,
    mode: userB.mode,
    accessToken: maskToken(userB.accessToken),
  });
  console.log('[fixture] listing', {
    id: listing.id,
    status: listing.status,
    ownerId: listing.owner_id,
  });
  console.log('[fixture] chat', {
    id: chat.id,
    buyerId: chat.buyerId ?? chat.buyer_id,
    sellerId: chat.sellerId ?? chat.seller_id,
  });
}

main().catch((error) => {
  console.error('[fixture] failed:', error.message);
  process.exit(1);
});
