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

/**
 * Creates a Keycloak user and sets an initial password.
 */
export const createKeycloakUser = async (input: CreateUserInput): Promise<void> => {
  const token = await adminAccessToken()
  const body = {
    username: input.username,
    enabled: true,
    email: input.email,
    emailVerified: Boolean(input.email),
    credentials: [
      {
        type: 'password',
        value: input.password,
        temporary: false,
      },
    ],
  }

  const response = await fetch(`${realmAdminBase()}/users`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })

  if (response.status === 201 || response.status === 204) {
    return
  }

  if (response.status === 409) {
    throw new AppError(409, 'USERNAME_TAKEN', 'That username is already taken.')
  }

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

export const isRegistrationEnabled = hasKeycloakClientSecret
