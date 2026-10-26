import { Hono } from 'hono'
import { z } from 'zod'
import { AppError } from '../lib/errors.js'
import type { AuthVariables } from '../middleware/auth.js'
import { requireAuth } from '../middleware/auth.js'
import { buildProgressExport } from '../services/export-service.js'

const formatSchema = z.enum(['csv', 'anki'])

export const exportRoutes = new Hono<{ Variables: AuthVariables }>()

exportRoutes.use('*', requireAuth)

/**
 * Returns a CSV or Anki-importable backup of the learner's card progress.
 */
exportRoutes.get('/progress', async (c) => {
  const parsed = formatSchema.safeParse(c.req.query('format') ?? 'csv')
  if (!parsed.success) {
    throw new AppError(400, 'VALIDATION_ERROR', 'format must be csv or anki')
  }

  const payload = await buildProgressExport(c.get('user'), parsed.data)
  return c.json({
    data: payload,
    meta: { requestId: c.get('requestId') },
  })
})
