import { config, hasKeycloakClientSecret } from '../config.js'
import { AppError } from '../lib/errors.js'
import { withKeycloakClient } from '../lib/keycloak-form.js'

type TokenResponse = {
  access_token?: string
  error_description?: string
}

type KeycloakUser = {
  id?: string
  username?: string
  email?: string
  firstName?: string
  lastName?: string
  enabled?: boolean
  emailVerified?: boolean
  requiredActions?: string[]
  attributes?: Record<string, unknown>
}

type CreateUserInput = {
  username: string
  password: string
  firstName: string
  lastName: string
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

const findUserByUsername = async (
  token: string,
  username: string,
): Promise<KeycloakUser | null> => {
  const url = new URL(`${realmAdminBase()}/users`)
  url.searchParams.set('username', username)
  url.searchParams.set('exact', 'true')
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!response.ok) return null
  const users = (await response.json()) as KeycloakUser[]
  return users[0] ?? null
}

const getUser = async (token: string, userId: string): Promise<KeycloakUser | null> => {
  const response = await fetch(`${realmAdminBase()}/users/${userId}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!response.ok) return null
  return (await response.json()) as KeycloakUser
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

const putUser = async (token: string, payload: KeycloakUser): Promise<void> => {
  if (!payload.id) {
    throw new AppError(502, 'REGISTER_FAILED', 'Keycloak user id missing.')
  }

  const response = await fetch(`${realmAdminBase()}/users/${payload.id}`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      ...payload,
      enabled: true,
      emailVerified: true,
      requiredActions: [],
    }),
  })

  if (!response.ok) {
    const text = await response.text()
    throw new AppError(
      502,
      'REGISTER_FAILED',
      text.trim() || 'Could not finish setting up the account in Keycloak.',
    )
  }

  const refreshed = await getUser(token, payload.id)
  const remaining = refreshed?.requiredActions ?? []
  if (remaining.length > 0) {
    throw new AppError(
      502,
      'REGISTER_FAILED',
      `Account still has required Keycloak actions: ${remaining.join(', ')}.`,
    )
  }
}

/**
 * Repairs an existing user so password grant can succeed.
 * Clears required actions. Does not invent a name when one is already set.
 */
export const prepareUserForLogin = async (username: string): Promise<boolean> => {
  if (!hasKeycloakClientSecret()) return false
  try {
    const token = await adminAccessToken()
    const user = await findUserByUsername(token, username)
    if (!user?.id) return false

    await putUser(token, {
      id: user.id,
      username: user.username ?? username,
      email: user.email,
      firstName: user.firstName?.trim() || undefined,
      lastName: user.lastName?.trim() || undefined,
      attributes: user.attributes,
    })
    return true
  } catch (error) {
    console.warn('prepareUserForLogin failed', username, error)
    return false
  }
}

/**
 * Creates a Keycloak user with the learner's real name, then sets a permanent password.
 */
export const createKeycloakUser = async (input: CreateUserInput): Promise<void> => {
  const token = await adminAccessToken()
  const body = {
    username: input.username,
    enabled: true,
    email: input.email,
    firstName: input.firstName,
    lastName: input.lastName,
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
    (await findUserByUsername(token, input.username))?.id

  if (!userId) {
    throw new AppError(
      502,
      'REGISTER_FAILED',
      'Account was created but could not be finalized. Try signing in.',
    )
  }

  await setPassword(token, userId, input.password)

  const created = (await getUser(token, userId)) ?? {
    id: userId,
    username: input.username,
  }

  await putUser(token, {
    id: created.id,
    username: created.username ?? input.username,
    email: input.email ?? created.email,
    firstName: input.firstName,
    lastName: input.lastName,
    attributes: created.attributes,
  })
}

/**
 * Updates first and last name for an existing Keycloak user (id = JWT sub).
 */
export const updateKeycloakNames = async (
  keycloakSub: string,
  names: { firstName: string; lastName: string },
): Promise<void> => {
  if (!hasKeycloakClientSecret()) {
    throw new AppError(
      503,
      'PROFILE_UPDATE_DISABLED',
      'Name updates are not configured on this server.',
    )
  }

  const token = await adminAccessToken()
  const existing = await getUser(token, keycloakSub)
  if (!existing?.id) {
    throw new AppError(404, 'USER_NOT_FOUND', 'Keycloak user not found.')
  }

  await putUser(token, {
    id: existing.id,
    username: existing.username,
    email: existing.email,
    firstName: names.firstName,
    lastName: names.lastName,
    attributes: existing.attributes,
  })
}

export const isRegistrationEnabled = hasKeycloakClientSecret

export const isAccountNotFullySetUp = (message: string): boolean =>
  message.toLowerCase().includes('not fully set up')
