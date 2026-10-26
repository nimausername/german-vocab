import { Hono } from 'hono'
import { z } from 'zod'
import { config } from '../config.js'
import { AppError } from '../lib/errors.js'
import { withKeycloakClient } from '../lib/keycloak-form.js'
import { createKeycloakUser, isRegistrationEnabled } from '../services/keycloak-admin.js'

const loginSchema = z.object({
  username: z.string().min(1),
  password: z.string().min(1),
})

const registerSchema = z.object({
  username: z
    .string()
    .trim()
    .min(3)
    .max(64)
    .regex(/^[a-zA-Z0-9._-]+$/, 'Use letters, numbers, dots, underscores, or hyphens'),
  password: z.string().min(8).max(128),
  email: z.preprocess(
    (value) => (typeof value === 'string' && value.trim() === '' ? undefined : value),
    z.string().trim().email().optional(),
  ),
})

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
})

type AuthRouteVariables = {
  requestId: string
}

type TokenJson = Record<string, unknown>

const passwordGrant = async (username: string, password: string): Promise<TokenJson> => {
  const form = withKeycloakClient(
    new URLSearchParams({
      grant_type: 'password',
      username,
      password,
    }),
  )

  const response = await fetch(config.KEYCLOAK_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  })

  const data = (await response.json()) as TokenJson
  if (!response.ok) {
    throw new AppError(
      401,
      'LOGIN_FAILED',
      typeof data.error_description === 'string'
        ? data.error_description
        : 'Invalid username or password',
    )
  }
  return data
}

const tokenPayload = (data: TokenJson, requestId: string) => ({
  data: {
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresIn: data.expires_in,
    refreshExpiresIn: data.refresh_expires_in,
    tokenType: data.token_type,
  },
  meta: { requestId },
})

export const authRoutes = new Hono<{ Variables: AuthRouteVariables }>()

/**
 * Proxies Keycloak password grant so the iPad app stays in-app.
 */
authRoutes.post('/login', async (c) => {
  const body = loginSchema.parse(await c.req.json())
  const data = await passwordGrant(body.username, body.password)
  return c.json(tokenPayload(data, c.get('requestId')))
})

/**
 * Creates a Keycloak user via Admin API, then signs them in.
 */
authRoutes.post('/register', async (c) => {
  if (!isRegistrationEnabled()) {
    throw new AppError(
      503,
      'REGISTER_DISABLED',
      'Account creation is not configured on this server.',
    )
  }

  const body = registerSchema.parse(await c.req.json())

  await createKeycloakUser({
    username: body.username,
    password: body.password,
    email: typeof body.email === 'string' ? body.email : undefined,
  })

  const data = await passwordGrant(body.username, body.password)
  return c.json(tokenPayload(data, c.get('requestId')), 201)
})

authRoutes.post('/refresh', async (c) => {
  const body = refreshSchema.parse(await c.req.json())

  const form = withKeycloakClient(
    new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: body.refreshToken,
    }),
  )

  const response = await fetch(config.KEYCLOAK_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  })

  const data = (await response.json()) as TokenJson

  if (!response.ok) {
    throw new AppError(401, 'REFRESH_FAILED', 'Session expired. Please sign in again.')
  }

  return c.json(tokenPayload(data, c.get('requestId')))
})
