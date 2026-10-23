import { Hono } from 'hono'
import { z } from 'zod'
import { config } from '../config.js'
import { AppError } from '../lib/errors.js'

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
})

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
})

type AuthRouteVariables = {
  requestId: string
}

export const authRoutes = new Hono<{ Variables: AuthRouteVariables }>()

/**
 * Proxies Keycloak password grant so the iPad app stays in-app.
 */
authRoutes.post('/login', async (c) => {
  const body = loginSchema.parse(await c.req.json())

  const form = new URLSearchParams({
    grant_type: 'password',
    client_id: config.KEYCLOAK_CLIENT_ID,
    username: body.username,
    password: body.password,
  })

  const response = await fetch(config.KEYCLOAK_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  })

  const data = (await response.json()) as Record<string, unknown>

  if (!response.ok) {
    throw new AppError(
      401,
      'LOGIN_FAILED',
      typeof data.error_description === 'string'
        ? data.error_description
        : 'Invalid username or password',
    )
  }

  return c.json({
    data: {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresIn: data.expires_in,
      refreshExpiresIn: data.refresh_expires_in,
      tokenType: data.token_type,
    },
    meta: { requestId: c.get('requestId') },
  })
})

authRoutes.post('/refresh', async (c) => {
  const body = refreshSchema.parse(await c.req.json())

  const form = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: config.KEYCLOAK_CLIENT_ID,
    refresh_token: body.refreshToken,
  })

  const response = await fetch(config.KEYCLOAK_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  })

  const data = (await response.json()) as Record<string, unknown>

  if (!response.ok) {
    throw new AppError(401, 'REFRESH_FAILED', 'Session expired. Please sign in again.')
  }

  return c.json({
    data: {
      accessToken: data.access_token,
      refreshToken: data.refresh_token,
      expiresIn: data.expires_in,
      refreshExpiresIn: data.refresh_expires_in,
      tokenType: data.token_type,
    },
    meta: { requestId: c.get('requestId') },
  })
})
