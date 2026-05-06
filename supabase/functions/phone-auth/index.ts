import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  })
}

function normalizePhone(raw: string) {
  const digits = raw.replace(/\D/g, '')
  if (!digits) return ''

  let local = digits
  if (
    local.length === 11 &&
    (local.startsWith('7') || local.startsWith('8'))
  ) {
    local = local.slice(1)
  }

  if (local.length !== 10) return ''
  return `+7${local}`
}

function normalizeEmail(raw: string) {
  return raw.trim().toLowerCase()
}

function isValidPhonePassword(password: string) {
  return /^\d{8,}$/.test(password)
}

async function callSmsRu(
  path: string,
  query: Record<string, string>,
) {
  const apiId =
    Deno.env.get('SMS_RU_API_ID')?.trim() ||
    '4A57DED4-EF6C-FF72-6F7B-7AF0E542DC74'

  if (!apiId) {
    throw new Error('Не настроен SMS_RU_API_ID')
  }

  const url = new URL(`https://sms.ru${path}`)
  url.searchParams.set('api_id', apiId)
  url.searchParams.set('json', '1')
  for (const [key, value] of Object.entries(query)) {
    url.searchParams.set(key, value)
  }

  const response = await fetch(url)
  const raw = await response.text()
  const body = raw.trim().length === 0
    ? {}
    : JSON.parse(raw) as Record<string, unknown>

  if (!response.ok) {
    const error = `${body.error ?? body.status_text ?? 'Ошибка sms.ru'}`
      .trim()
    throw new Error(error || 'Ошибка sms.ru')
  }

  const status = `${body.status ?? ''}`.trim()
  if (status.length > 0 && status !== 'OK') {
    const error = `${body.status_text ?? 'Не удалось выполнить запрос к sms.ru'}`
      .trim()
    throw new Error(error || 'Не удалось выполнить запрос к sms.ru')
  }

  return body
}

function phoneEmail(phone: string) {
  const digits = phone.replace(/\D/g, '')
  return `phone_${digits}@phone.atta.local`
}

type AdminClient = ReturnType<typeof createClient>

type PublicUserRow = {
  id?: string | null
  email?: string | null
}

type ListingOwnerRow = {
  id?: string | null
  photo_urls?: string[] | null
}

type ChatIdRow = {
  id?: string | null
}

type ChatImageRow = {
  image_url?: string | null
}

async function findPublicUsersByPhone(admin: AdminClient, phone: string) {
  const rowRes = await admin
    .from('users')
    .select('id,email')
    .eq('phone', phone)

  if (rowRes.error != null) {
    throw new Error(rowRes.error.message)
  }

  return ((rowRes.data ?? []) as PublicUserRow[]).filter((row) => row != null)
}

function isMissingAuthUserError(message: string) {
  const normalized = message.trim().toLowerCase()
  return normalized.includes('not found') || normalized.includes('user not found')
}

function isMissingRelationError(message: string) {
  const normalized = message.trim().toLowerCase()
  return normalized.includes('relation') && normalized.includes('does not exist')
}

function isMissingColumnError(message: string) {
  const normalized = message.trim().toLowerCase()
  return (
    (normalized.includes('column') && normalized.includes('does not exist')) ||
    (normalized.includes('could not find') &&
      normalized.includes('column') &&
      normalized.includes('schema cache'))
  )
}

function isIgnorableSchemaError(message: string) {
  return isMissingRelationError(message) || isMissingColumnError(message)
}

async function deleteStalePublicUsers(admin: AdminClient, userIds: string[]) {
  const uniqueIds = [...new Set(userIds.map((id) => id.trim()).filter(Boolean))]
  if (uniqueIds.length === 0) return

  const deleteRes = await admin.from('users').delete().in('id', uniqueIds)
  if (deleteRes.error != null) {
    throw new Error(deleteRes.error.message)
  }
}

async function resolveAuthIdentityByPhone(admin: AdminClient, phone: string) {
  const publicUsers = await findPublicUsersByPhone(admin, phone)
  const stalePublicUserIds: string[] = []

  for (const publicUser of publicUsers) {
    const publicUserId = `${publicUser.id ?? ''}`.trim()
    if (!publicUserId) continue

    const authUserRes = await admin.auth.admin.getUserById(publicUserId)
    if (authUserRes.error != null) {
      if (isMissingAuthUserError(authUserRes.error.message)) {
        stalePublicUserIds.push(publicUserId)
        continue
      }

      throw new Error(authUserRes.error.message)
    }

    const authUser = authUserRes.data.user
    if (authUser == null) {
      stalePublicUserIds.push(publicUserId)
      continue
    }

    if (stalePublicUserIds.length > 0) {
      await deleteStalePublicUsers(admin, stalePublicUserIds)
    }

    const authEmail = `${authUser.email ?? ''}`.trim()
    return {
      user: authUser,
      email: authEmail.length > 0 ? authEmail : phoneEmail(phone),
    }
  }

  if (stalePublicUserIds.length > 0) {
    await deleteStalePublicUsers(admin, stalePublicUserIds)
  }

  return {
    user: null,
    email: phoneEmail(phone),
  }
}

async function upsertPublicUser(
  admin: AdminClient,
  {
    userId,
    email,
    displayName,
    phone,
    phoneVerified,
  }: {
    userId: string
    email?: string
    displayName?: string
    phone?: string
    phoneVerified?: boolean
  },
) {
  const payload: Record<string, unknown> = { id: userId }
  const cleanEmail = (email ?? '').trim()
  const cleanDisplayName = (displayName ?? '').trim()
  const cleanPhone = (phone ?? '').trim()

  if (cleanEmail.length > 0) {
    payload.email = cleanEmail
  }
  if (cleanDisplayName.length > 0) {
    payload.display_name = cleanDisplayName
    payload.name = cleanDisplayName
  }
  if (cleanPhone.length > 0) {
    payload.phone = cleanPhone
  }
  if (phoneVerified != null) {
    payload.phone_verified = phoneVerified
  }

  const upsertRes = await admin.from('users').upsert(payload, {
    onConflict: 'id',
  })

  if (upsertRes.error != null) {
    throw new Error(upsertRes.error.message)
  }
}

async function signInWithResolvedEmail(
  admin: AdminClient,
  {
    email,
    password,
  }: {
    email: string
    password: string
  },
) {
  const signInRes = await admin.auth.signInWithPassword({
    email,
    password,
  })

  if (signInRes.error != null || signInRes.data.session == null) {
    throw new Error(signInRes.error?.message ?? 'Не удалось открыть сессию')
  }

  return signInRes
}

async function requireCurrentUser(
  req: Request,
  supabaseUrl: string,
  anonKey: string,
) {
  const authHeader = req.headers.get('Authorization') ?? ''
  if (authHeader.trim().length === 0) {
    throw new Error('Нужна авторизация')
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: authHeader } },
  })

  const userRes = await userClient.auth.getUser()
  if (userRes.error != null || userRes.data.user == null) {
    throw new Error(userRes.error?.message ?? 'Пользователь не найден')
  }

  return userRes.data.user
}

function extractStoragePathFromPublicUrl(
  value: string,
  bucket: string,
) {
  const raw = value.trim()
  if (!raw) return ''

  if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
    return raw.replace(/^\/+/, '')
  }

  try {
    const url = new URL(raw)
    const marker = `/object/public/${bucket}/`
    const idx = url.pathname.indexOf(marker)
    if (idx === -1) return ''
    const encodedPath = url.pathname.slice(idx + marker.length)
    return decodeURIComponent(encodedPath).replace(/^\/+/, '')
  } catch (_) {
    return ''
  }
}

async function deleteStorageByPrefixes(
  admin: AdminClient,
  bucket: string,
  prefixes: string[],
) {
  const normalized = [...new Set(prefixes.map((x) => x.trim()).filter(Boolean))]
  for (const prefix of normalized) {
    const listRes = await admin.storage.from(bucket).list(prefix, {
      limit: 1000,
      offset: 0,
    })
    if (listRes.error != null) {
      throw new Error(`storage list ${bucket}/${prefix}: ${listRes.error.message}`)
    }

    const paths = (listRes.data ?? [])
      .map((entry) => entry.name?.trim() ?? '')
      .filter((name) => name.length > 0)
      .map((name) => `${prefix}/${name}`)

    if (paths.length === 0) continue

    const removeRes = await admin.storage.from(bucket).remove(paths)
    if (removeRes.error != null) {
      throw new Error(`storage remove ${bucket}/${prefix}: ${removeRes.error.message}`)
    }
  }
}

async function deleteStorageByPaths(
  admin: AdminClient,
  bucket: string,
  paths: string[],
) {
  const normalized = [...new Set(paths.map((x) => x.trim()).filter(Boolean))]
  if (normalized.length === 0) return
  const removeRes = await admin.storage.from(bucket).remove(normalized)
  if (removeRes.error != null) {
    throw new Error(`storage remove ${bucket}: ${removeRes.error.message}`)
  }
}

async function runDeleteStep(
  step: string,
  action: () => Promise<void>,
) {
  try {
    await action()
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : 'Неизвестная ошибка удаления'
    throw new Error(`Шаг "${step}" не выполнен: ${message}`)
  }
}

function hasSchemaColumn(tableColumns: string[], column: string) {
  return tableColumns.includes(column.trim())
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const anonKey =
      Deno.env.get('SUPABASE_ANON_KEY') ??
      req.headers.get('apikey') ??
      ''

    if (!supabaseUrl || !serviceRoleKey) {
      return json(
        { error: 'Не настроены SUPABASE_URL или SUPABASE_SERVICE_ROLE_KEY' },
        500,
      )
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const body = await req.json()
    const action = `${body?.action ?? ''}`.trim()

    if (action === 'callcheck_status') {
      const checkId = `${body?.check_id ?? ''}`.trim()
      if (checkId.length === 0) {
        return json({ error: 'Нужен check_id' }, 400)
      }

      const result = await callSmsRu('/callcheck/status', {
        check_id: checkId,
      })
      return json(result)
    }

    if (action === 'link_email') {
      const email = normalizeEmail(`${body?.email ?? ''}`)
      if (email.length === 0 || !email.includes('@')) {
        return json({ error: 'Введите корректный email' }, 400)
      }
      if (!anonKey) {
        return json({ error: 'Не настроен anon key для проверки пользователя' }, 500)
      }

      const currentUser = await requireCurrentUser(req, supabaseUrl, anonKey)
      const currentUserId = currentUser.id
      const currentMetadata = currentUser.user_metadata ?? {}

      const updateRes = await admin.auth.admin.updateUserById(currentUserId, {
        email,
        email_confirm: true,
        user_metadata: {
          ...currentMetadata,
          email,
        },
      })

      if (updateRes.error != null) {
        return json({ error: updateRes.error.message }, 400)
      }

      await upsertPublicUser(admin, {
        userId: currentUserId,
        email,
      })

      return json({
        email,
        user: updateRes.data.user,
      })
    }

    if (action === 'delete_account') {
      if (!anonKey) {
        return json({ error: 'Не настроен anon key для проверки пользователя' }, 500)
      }

      const currentUser = await requireCurrentUser(req, supabaseUrl, anonKey)
      const currentUserId = currentUser.id
      const listingRowsRes = await admin
        .from('listings')
        .select('id,photo_urls')
        .eq('owner_id', currentUserId)
      if (listingRowsRes.error != null && !isIgnorableSchemaError(listingRowsRes.error.message)) {
        return json({ error: `Не удалось получить объявления: ${listingRowsRes.error.message}` }, 400)
      }
      const listingRows = (listingRowsRes.data ?? []) as ListingOwnerRow[]
      const listingIds = listingRows
        .map((row) => `${row.id ?? ''}`.trim())
        .filter((id) => id.length > 0)

      const chatRowsRes = await admin
        .from('chats')
        .select('id')
        .or(`buyer_id.eq.${currentUserId},seller_id.eq.${currentUserId}`)
      if (chatRowsRes.error != null && !isIgnorableSchemaError(chatRowsRes.error.message)) {
        return json({ error: `Не удалось получить чаты: ${chatRowsRes.error.message}` }, 400)
      }
      const chatIds = ((chatRowsRes.data ?? []) as ChatIdRow[])
        .map((row) => `${row.id ?? ''}`.trim())
        .filter((id) => id.length > 0)

      const sentImageRowsRes = await admin
        .from('chat_messages')
        .select('image_url')
        .eq('sender_id', currentUserId)
        .not('image_url', 'is', null)
      if (sentImageRowsRes.error != null && !isIgnorableSchemaError(sentImageRowsRes.error.message)) {
        return json({ error: `Не удалось получить изображения чатов: ${sentImageRowsRes.error.message}` }, 400)
      }
      const sentImageRows = (sentImageRowsRes.data ?? []) as ChatImageRow[]

      const listingPhotoPaths = listingRows
        .flatMap((row) => (row.photo_urls ?? []))
        .map((raw) => extractStoragePathFromPublicUrl(`${raw ?? ''}`, 'listing-photos'))
        .filter((path) => path.length > 0)

      const chatImagePaths = sentImageRows
        .map((row) => extractStoragePathFromPublicUrl(`${row.image_url ?? ''}`, 'chat_images'))
        .filter((path) => path.length > 0)

      const userMeta = currentUser.user_metadata ?? {}
      const avatarCandidates = [
        `${userMeta.avatar_url ?? ''}`,
        `${userMeta.photo_url ?? ''}`,
        `${userMeta.photoUrl ?? ''}`,
        `${userMeta.picture ?? ''}`,
      ]
      const avatarPaths = avatarCandidates
        .map((raw) => extractStoragePathFromPublicUrl(raw, 'avatars'))
        .filter((path) => path.length > 0)
      avatarPaths.push(`${currentUserId}/avatar.jpg`, `${currentUserId}/avatar.png`)

      try {
        await runDeleteStep('Удаление аватаров из Storage', async () => {
          await deleteStorageByPrefixes(admin, 'avatars', [currentUserId])
          await deleteStorageByPaths(admin, 'avatars', avatarPaths)
        })

        await runDeleteStep('Удаление фото объявлений из Storage', async () => {
          await deleteStorageByPrefixes(admin, 'listing-photos', listingIds)
          await deleteStorageByPaths(admin, 'listing-photos', listingPhotoPaths)
        })

        await runDeleteStep('Удаление изображений чатов из Storage', async () => {
          await deleteStorageByPrefixes(admin, 'chat_images', chatIds)
          await deleteStorageByPaths(admin, 'chat_images', chatImagePaths)
        })

        await runDeleteStep('Удаление сохранённых поисков', async () => {
          const res = await admin.from('saved_searches').delete().eq('user_id', currentUserId)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление избранного', async () => {
          const byUser = await admin.from('favorites').delete().eq('user_id', currentUserId)
          if (byUser.error != null && !isIgnorableSchemaError(byUser.error.message)) {
            throw new Error(byUser.error.message)
          }
          if (listingIds.length > 0) {
            const byListing = await admin.from('favorites').delete().in('listing_id', listingIds)
            if (byListing.error != null && !isIgnorableSchemaError(byListing.error.message)) {
              throw new Error(byListing.error.message)
            }
          }
        })

        await runDeleteStep('Удаление подписок', async () => {
          const res = await admin
            .from('user_follows')
            .delete()
            .or(`follower_id.eq.${currentUserId},seller_id.eq.${currentUserId}`)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление user_presence', async () => {
          const res = await admin.from('user_presence').delete().eq('user_id', currentUserId)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление уведомлений', async () => {
          const res = await admin.from('user_notifications').delete().eq('user_id', currentUserId)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление сообщений чатов', async () => {
          const sent = await admin.from('chat_messages').delete().eq('sender_id', currentUserId)
          if (sent.error != null && !isIgnorableSchemaError(sent.error.message)) {
            throw new Error(sent.error.message)
          }
          if (chatIds.length > 0) {
            const byChat = await admin.from('chat_messages').delete().in('chat_id', chatIds)
            if (byChat.error != null && !isIgnorableSchemaError(byChat.error.message)) {
              throw new Error(byChat.error.message)
            }
          }
        })

        await runDeleteStep('Удаление чатов', async () => {
          const res = await admin
            .from('chats')
            .delete()
            .or(`buyer_id.eq.${currentUserId},seller_id.eq.${currentUserId}`)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление отзывов', async () => {
          const res = await admin
            .from('reviews')
            .delete()
            .or(`reviewer_id.eq.${currentUserId},seller_id.eq.${currentUserId}`)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление жалоб', async () => {
          const res = await admin.from('reports').delete().eq('reporter_id', currentUserId)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Обезличивание ссылок в reports', async () => {
          const schemaRes = await admin
            .from('reports')
            .select('*')
            .limit(1)
          if (schemaRes.error != null && !isIgnorableSchemaError(schemaRes.error.message)) {
            throw new Error(schemaRes.error.message)
          }

          const firstRow = (schemaRes.data?.[0] ?? {}) as Record<string, unknown>
          const columns = Object.keys(firstRow)

          const updatePayload: Record<string, unknown> = {}
          const filters: string[] = []
          if (hasSchemaColumn(columns, 'listing_owner_id')) {
            updatePayload.listing_owner_id = null
            filters.push(`listing_owner_id.eq.${currentUserId}`)
          }
          if (hasSchemaColumn(columns, 'admin_uid')) {
            updatePayload.admin_uid = null
            filters.push(`admin_uid.eq.${currentUserId}`)
          }
          if (hasSchemaColumn(columns, 'handled_by')) {
            updatePayload.handled_by = null
            filters.push(`handled_by.eq.${currentUserId}`)
          }

          if (Object.keys(updatePayload).length === 0 || filters.length === 0) {
            return
          }

          const res = await admin
            .from('reports')
            .update(updatePayload)
            .or(filters.join(','))
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление поддержки', async () => {
          const ticketRows = await admin
            .from('support_tickets')
            .select('id')
            .or(`uid.eq.${currentUserId},user_id.eq.${currentUserId}`)
          if (ticketRows.error != null && !isIgnorableSchemaError(ticketRows.error.message)) {
            throw new Error(ticketRows.error.message)
          }

          const ticketIds = ((ticketRows.data ?? []) as ChatIdRow[])
            .map((row) => `${row.id ?? ''}`.trim())
            .filter((id) => id.length > 0)

          if (ticketIds.length > 0) {
            const messages = await admin
              .from('support_messages')
              .delete()
              .in('ticket_id', ticketIds)
            if (messages.error != null && !isIgnorableSchemaError(messages.error.message)) {
              throw new Error(messages.error.message)
            }
          }

          const tickets = await admin
            .from('support_tickets')
            .delete()
            .or(`uid.eq.${currentUserId},user_id.eq.${currentUserId}`)
          if (tickets.error != null && !isIgnorableSchemaError(tickets.error.message)) {
            throw new Error(tickets.error.message)
          }
        })

        await runDeleteStep('Удаление объявлений', async () => {
          const res = await admin.from('listings').delete().eq('owner_id', currentUserId)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление admin_users', async () => {
          const res = await admin.from('admin_users').delete().eq('uid', currentUserId)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление профиля users', async () => {
          const res = await admin.from('users').delete().eq('id', currentUserId)
          if (res.error != null && !isIgnorableSchemaError(res.error.message)) {
            throw new Error(res.error.message)
          }
        })

        await runDeleteStep('Удаление пользователя Auth', async () => {
          const res = await admin.auth.admin.deleteUser(currentUserId)
          if (res.error != null) {
            throw new Error(res.error.message)
          }
        })
      } catch (error) {
        const message = error instanceof Error
          ? error.message
          : 'Неизвестная ошибка удаления'
        return json({ error: message }, 400)
      }

      return json({ ok: true })
    }

    const phone = normalizePhone(`${body?.phone ?? ''}`)

    if (!phone) {
      return json({ error: 'Введите корректный номер телефона' }, 400)
    }

    if (action === 'callcheck_start') {
      const result = await callSmsRu('/callcheck/add', {
        phone: phone.replace(/\D/g, ''),
      })
      return json(result)
    }

    const resolvedIdentity = await resolveAuthIdentityByPhone(admin, phone)

    if (action === 'check_registration') {
      return json({
        registered: resolvedIdentity.user != null,
      })
    }

    const password = `${body?.password ?? ''}`.trim()
    if (!password) {
      return json({ error: 'Введите пароль' }, 400)
    }
    if (!isValidPhonePassword(password)) {
      return json({ error: 'Введите не менее 8 цифр' }, 400)
    }

    if (action === 'signup') {
      const displayName = `${body?.display_name ?? ''}`.trim()
      const acceptedLegal = body?.accepted_legal === true

      if (!displayName) {
        return json({ error: 'Введите имя' }, 400)
      }

      if (resolvedIdentity.user != null) {
        try {
          const signInRes = await signInWithResolvedEmail(admin, {
            email: resolvedIdentity.email,
            password,
          })

          return json({
            session: signInRes.data.session,
            refresh_token: signInRes.data.session.refresh_token,
            user: signInRes.data.user,
          })
        } catch (_) {
          return json(
            { error: '\u042d\u0442\u043e\u0442 \u043d\u043e\u043c\u0435\u0440 \u0443\u0436\u0435 \u0437\u0430\u0440\u0435\u0433\u0438\u0441\u0442\u0440\u0438\u0440\u043e\u0432\u0430\u043d. \u041f\u043e\u043f\u0440\u043e\u0431\u0443\u0439\u0442\u0435 \u0432\u043e\u0439\u0442\u0438.' },
            400,
          )
        }
      }

      const initialEmail = phoneEmail(phone)
      const createRes = await admin.auth.admin.createUser({
        email: initialEmail,
        password,
        email_confirm: true,
        user_metadata: {
          name: displayName,
          displayName,
          display_name: displayName,
          phone,
          phone_verified: true,
          acceptedTerms: acceptedLegal,
          acceptedPrivacyPolicy: acceptedLegal,
          registrationMethod: 'phone',
        },
      })

      if (createRes.error != null) {
        return json({ error: createRes.error.message }, 400)
      }

      const user = createRes.data.user
      if (user == null) {
        return json({ error: 'Не удалось создать пользователя' }, 500)
      }

      await upsertPublicUser(admin, {
        userId: user.id,
        email: initialEmail,
        displayName,
        phone,
        phoneVerified: true,
      })

      const signInRes = await signInWithResolvedEmail(admin, {
        email: initialEmail,
        password,
      })

      return json({
        session: signInRes.data.session,
        refresh_token: signInRes.data.session.refresh_token,
        user: signInRes.data.user,
      })
    }

    if (action === 'login') {
      try {
        const signInRes = await signInWithResolvedEmail(admin, {
          email: resolvedIdentity.email,
          password,
        })

        return json({
          session: signInRes.data.session,
          refresh_token: signInRes.data.session.refresh_token,
          user: signInRes.data.user,
        })
      } catch (_) {
        return json({ error: 'Неверный номер телефона или пароль.' }, 400)
      }
    }

    if (action === 'reset_password') {
      const user = resolvedIdentity.user
      if (user == null) {
        return json({ error: 'Аккаунт с этим номером не найден.' }, 404)
      }

      const updateRes = await admin.auth.admin.updateUserById(user.id, {
        password,
        user_metadata: {
          ...(user.user_metadata ?? {}),
          phone,
          phone_verified: true,
        },
      })

      if (updateRes.error != null) {
        return json({ error: updateRes.error.message }, 400)
      }

      await upsertPublicUser(admin, {
        userId: user.id,
        email: resolvedIdentity.email,
        phone,
        phoneVerified: true,
      })

      const signInRes = await signInWithResolvedEmail(admin, {
        email: resolvedIdentity.email,
        password,
      })

      return json({
        session: signInRes.data.session,
        refresh_token: signInRes.data.session.refresh_token,
        user: signInRes.data.user,
      })
    }

    return json({ error: 'Неизвестное действие' }, 400)
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Неизвестная ошибка backend'
    return json({ error: message }, 500)
  }
})
