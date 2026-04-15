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

function phoneEmail(phone: string) {
  const digits = phone.replace(/\D/g, '')
  return `phone_${digits}@phone.atta.local`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

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
    const phone = normalizePhone(`${body?.phone ?? ''}`)
    const password = `${body?.password ?? ''}`.trim()

    if (!phone) {
      return json({ error: 'Введите корректный номер телефона' }, 400)
    }
    if (!password) {
      return json({ error: 'Введите пароль' }, 400)
    }

    const email = phoneEmail(phone)

    if (action == 'signup') {
      const displayName = `${body?.display_name ?? ''}`.trim()
      const acceptedLegal = body?.accepted_legal === true

      if (!displayName) {
        return json({ error: 'Введите имя' }, 400)
      }

      const createRes = await admin.auth.admin.createUser({
        email,
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
        const message = createRes.error.message.toLowerCase()
        if (
          message.includes('already') ||
          message.includes('registered') ||
          message.includes('exists')
        ) {
          return json(
            { error: 'Этот номер уже зарегистрирован. Попробуйте войти.' },
            400,
          )
        }

        return json({ error: createRes.error.message }, 400)
      }

      const user = createRes.data.user
      if (user == null) {
        return json({ error: 'Не удалось создать пользователя' }, 500)
      }

      const upsertRes = await admin.from('users').upsert(
        {
          id: user.id,
          email,
          display_name: displayName,
          name: displayName,
          phone,
          phone_verified: true,
        },
        { onConflict: 'id' },
      )

      if (upsertRes.error != null) {
        return json({ error: upsertRes.error.message }, 400)
      }

      const signInRes = await admin.auth.signInWithPassword({
        email,
        password,
      })

      if (signInRes.error != null || signInRes.data.session == null) {
        return json(
          { error: signInRes.error?.message ?? 'Не удалось открыть сессию' },
          400,
        )
      }

      return json({
        session: signInRes.data.session,
        refresh_token: signInRes.data.session.refresh_token,
        user: signInRes.data.user,
      })
    }

    if (action == 'login') {
      const signInRes = await admin.auth.signInWithPassword({
        email,
        password,
      })

      if (signInRes.error != null || signInRes.data.session == null) {
        return json(
          { error: 'Неверный номер телефона или пароль.' },
          400,
        )
      }

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
