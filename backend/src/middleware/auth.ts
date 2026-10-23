import { createMiddleware } from 'hono/factory'
import { createRemoteJWKSet, jwtVerify } from 'jose'
import { config } from '../config.js'
import { AppError } from '../lib/errors.js'
import { ensureUserProfile } from '../services/user-service.js'
import type { UserProfile } from '../db/schema.js'

const jwks = createRemoteJWKSet(
  new URL(`${config.KEYCLOAK_ISSUER}/protocol/openid-connect/certs`),
)

export type AuthVariables = {
  user: UserProfile
  requestId: string
}

type AccessTokenPayload = {
  sub: string
  email?: string
  name?: string
  preferred_username?: string
}

/**
 * Validates Keycloak bearer JWT and attaches the local user profile.
 */
export const requireAuth = createMiddleware<{ Variables: AuthVariables }>(
  async (c, next) => {
    const header = c.req.header('authorization')
    if (!header?.startsWith('Bearer ')) {
      throw new AppError(401, 'UNAUTHORIZED', 'Missing bearer token')
    }

    const token = header.slice('Bearer '.length)
    let payload: AccessTokenPayload

    try {
      const verified = await jwtVerify(token, jwks, {
        issuer: config.KEYCLOAK_ISSUER,
      })
      payload = verified.payload as AccessTokenPayload
    } catch {
      throw new AppError(401, 'UNAUTHORIZED', 'Invalid or expired token')
    }

    if (!payload.sub) {
      throw new AppError(401, 'UNAUTHORIZED', 'Token missing subject')
    }

    const displayName =
      payload.name ?? payload.preferred_username ?? payload.email ?? null

    const user = await ensureUserProfile({
      keycloakSub: payload.sub,
      email: payload.email ?? null,
      displayName,
    })

    c.set('user', user)
    await next()
  },
)
