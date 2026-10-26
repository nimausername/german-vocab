import 'dotenv/config'
import { z } from 'zod'

const envSchema = z.object({
  DATABASE_URL: z.string().min(1),
  PORT: z.coerce.number().default(3080),
  HOST: z.string().default('0.0.0.0'),
  KEYCLOAK_ISSUER: z.string().url(),
  KEYCLOAK_CLIENT_ID: z.string().min(1),
  KEYCLOAK_TOKEN_URL: z.string().url(),
  /**
   * Secret for the same confidential client used by login, refresh, and
   * Create Account. Leave empty only while the Keycloak client is still public
   * (login works; registration stays disabled).
   */
  KEYCLOAK_CLIENT_SECRET: z.string().optional().default(''),
  CORS_ORIGIN: z.string().default('*'),
})

const parsed = envSchema.safeParse(process.env)

if (!parsed.success) {
  console.error(parsed.error.flatten().fieldErrors)
  throw new Error('Invalid environment configuration')
}

export const config = parsed.data

/** True when the API can call Keycloak with a client secret. */
export const hasKeycloakClientSecret = (): boolean =>
  Boolean(config.KEYCLOAK_CLIENT_SECRET.trim())
