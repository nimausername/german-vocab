import { config, hasKeycloakClientSecret } from '../config.js'
import { AppError } from '../lib/errors.js'
import { withKeycloakClient } from '../lib/keycloak-form.js'

type TokenResponse = {
  access_token?: string
  error_description?: string
}

type CreateUserInput = {
  username: string
  password: string
  email?: string
}

const realmAdminBase = (): string => {
  // KEYCLOAK_ISSUER looks like https://host/realms/german-vocab
  return config.KEYCLOAK_ISSUER.replace('/realms/', '/admin/realms/')
}

/**
 * Fetches a service-account token that can create users (same app client).
 */
const adminAccessToken = async (): Promise<string> => {
  if (!hasKeycloakClientSecret()) {
    throw new AppError(
      503,
      'REGISTER_DISABLED',
      'Account creation is not configured on this server.',
    )
  }

  const form = withKeycloakClient(
    new URLSearchParams({
      grant_type: 'client_credentials',
    }),
  )

  const response = await fetch(config.KEYCLOAK_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  })
  const data = (await response.json()) as TokenResponse
  if (!response.ok || !data.access_token) {
    throw new AppError(
      503,
      'REGISTER_DISABLED',
      typeof data.error_description === 'string'
        ? data.error_description
        : 'Could not reach Keycloak admin. Enable Service accounts on the client and assign manage-users.',
    )
  }
  return data.access_token
}

const userIdFromLocation = (location: string | null): string | null => {
  if (!location) return null
  const parts = location.split('/').filter(Boolean)
  return parts.at(-1) ?? null
}

const findUserIdByUsername = async (token: string, username: string): Promise<string | null> => {
  const url = new URL(`${realmAdminBase()}/users`)
  url.searchParams.set('username', username)
  url.searchParams.set('exact', 'true')
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!response.ok) return null
  const users = (await response.json()) as Array<{ id?: string }>
  return users[0]?.id ?? null
}

const setPassword = async (token: string, userId: string, password: string): Promise<void> => {
  const response = await fetch(`${realmAdminBase()}/users/${userId}/reset-password`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      type: 'password',
      value: password,
      temporary: false,
    }),
  })
  if (!response.ok) {
    const text = await response.text()
    throw new AppError(
      502,
      'REGISTER_FAILED',
      text.trim() || 'Account was created but the password could not be set.',
    )
  }
}

const clearRequiredActions = async (token: string, userId: string): Promise<void> => {
  const getResponse = await fetch(`${realmAdminBase()}/users/${userId}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!getResponse.ok) return

  const existing = (await getResponse.json()) as Record<string, unknown>
  const response = await fetch(`${realmAdminBase()}/users/${userId}`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      id: existing.id,
      username: existing.username,
      email: existing.email,
      firstName: existing.firstName,
      lastName: existing.lastName,
      attributes: existing.attributes,
      enabled: true,
      emailVerified: true,
      requiredActions: [],
    }),
  })
  // Non-fatal: password grant may still work without this.
  if (!response.ok) {
    console.warn('Could not clear Keycloak requiredActions for', userId, response.status)
  }
}

/**
 * Creates a Keycloak user, sets a permanent password, and clears blocking actions.
 */
export const createKeycloakUser = async (input: CreateUserInput): Promise<void> => {
  const token = await adminAccessToken()
  const body = {
    username: input.username,
    enabled: true,
    email: input.email,
    // Always mark verified for API-created accounts so password grant is not blocked.
    emailVerified: true,
    requiredActions: [] as string[],
  }

  const response = await fetch(`${realmAdminBase()}/users`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })

  if (response.status === 409) {
    throw new AppError(409, 'USERNAME_TAKEN', 'That username is already taken. Try signing in.')
  }

  if (response.status !== 201 && response.status !== 204) {
    const text = await response.text()
    let message = 'Could not create the account.'
    try {
      const parsed = JSON.parse(text) as { errorMessage?: string; error?: string }
      message = parsed.errorMessage ?? parsed.error ?? message
    } catch {
      if (text.trim()) message = text.trim()
    }
    throw new AppError(502, 'REGISTER_FAILED', message)
  }

  const userId =
    userIdFromLocation(response.headers.get('location')) ??
    (await findUserIdByUsername(token, input.username))

  if (!userId) {
    throw new AppError(
      502,
      'REGISTER_FAILED',
      'Account was created but could not be finalized. Try signing in.',
    )
  }

  await setPassword(token, userId, input.password)
  await clearRequiredActions(token, userId)
}

export const isRegistrationEnabled = hasKeycloakClientSecret
