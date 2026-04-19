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
