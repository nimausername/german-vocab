import { config, hasKeycloakClientSecret } from '../config.js'

/**
 * Adds client_id and, when configured, client_secret to a Keycloak token form.
 */
export const withKeycloakClient = (form: URLSearchParams): URLSearchParams => {
  form.set('client_id', config.KEYCLOAK_CLIENT_ID)
  if (hasKeycloakClientSecret()) {
    form.set('client_secret', config.KEYCLOAK_CLIENT_SECRET)
  }
  return form
}
