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

function phoneEmail(phone: string) {
  const digits = phone.replace(/\D/g, '')
  return `phone_${digits}@phone.atta.local`
}

type AdminClient = ReturnType<typeof createClient>

type PublicUserRow = {
  id?: string | null
  email?: string | null
}

async function findPublicUserByPhone(admin: AdminClient, phone: string) {
  const rowRes = await admin
    .from('users')
    .select('id,email')
    .eq('phone', phone)
    .limit(1)
    .maybeSingle()

  if (rowRes.error != null) {
    throw new Error(rowRes.error.message)
  }

  return (rowRes.data ?? null) as PublicUserRow | null
}

async function resolveAuthIdentityByPhone(admin: AdminClient, phone: string) {
  const publicUser = await findPublicUserByPhone(admin, phone)
  const publicUserId = `${publicUser?.id ?? ''}`.trim()

  if (publicUserId.length > 0) {
    const authUserRes = await admin.auth.admin.getUserById(publicUserId)
    if (authUserRes.error != null) {
      throw new Error(authUserRes.error.message)
    }

    const authUser = authUserRes.data.user
    if (authUser != null) {
      const authEmail = `${authUser.email ?? ''}`.trim()
      return {
        user: authUser,
        email: authEmail.length > 0 ? authEmail : phoneEmail(phone),
      }
    }
  }

  const rowEmail = `${publicUser?.email ?? ''}`.trim()
  if (rowEmail.length > 0) {
    return {
      user: null,
      email: rowEmail,
    }
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
    const password = `${body?.password ?? ''}`.trim()

    if (!phone) {
      return json({ error: 'Введите корректный номер телефона' }, 400)
    }
    if (!password) {
      return json({ error: 'Введите пароль' }, 400)
    }

    const resolvedIdentity = await resolveAuthIdentityByPhone(admin, phone)

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

          const mergedMetadata = {
            ...(resolvedIdentity.user.user_metadata ?? {}),
            name: displayName,
            displayName,
            display_name: displayName,
            phone,
            phone_verified: true,
            acceptedTerms: acceptedLegal,
            acceptedPrivacyPolicy: acceptedLegal,
            registrationMethod: 'phone',
          }

          const updateRes = await admin.auth.admin.updateUserById(
            resolvedIdentity.user.id,
            {
              user_metadata: mergedMetadata,
            },
          )

          if (updateRes.error != null) {
            throw new Error(updateRes.error.message)
          }

          await upsertPublicUser(admin, {
            userId: resolvedIdentity.user.id,
            email: resolvedIdentity.email,
            displayName,
            phone,
            phoneVerified: true,
          })

          return json({
            session: signInRes.data.session,
            refresh_token: signInRes.data.session.refresh_token,
            user: signInRes.data.user,
          })
        } catch (_) {
          return json(
            { error: 'Этот номер уже зарегистрирован. Попробуйте войти.' },
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
