import { Hono } from 'hono'
import { z } from 'zod'
import { AppError } from '../lib/errors.js'
import type { AuthVariables } from '../middleware/auth.js'
import { requireAuth } from '../middleware/auth.js'
import { getWordById, listWords } from '../services/words-service.js'

const listQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  search: z.string().trim().max(100).optional(),
  cefrLevel: z.string().trim().max(8).optional(),
  gender: z.enum(['der', 'die', 'das']).optional(),
  status: z.enum(['all', 'learned', 'new']).default('all'),
})

export const wordRoutes = new Hono<{ Variables: AuthVariables }>()

wordRoutes.use('*', requireAuth)

wordRoutes.get('/', async (c) => {
  const parsed = listQuerySchema.safeParse({
    page: c.req.query('page') ?? '1',
    limit: c.req.query('limit') ?? '50',
    search: c.req.query('search') || undefined,
    cefrLevel: c.req.query('cefrLevel') || undefined,
    gender: c.req.query('gender') || undefined,
    status: c.req.query('status') || 'all',
  })

  if (!parsed.success) {
    throw new AppError(400, 'VALIDATION_ERROR', 'Invalid query parameters', [
      ...parsed.error.issues.map((issue) => ({
        field: issue.path.join('.') || 'query',
        reason: issue.message,
      })),
    ])
  }

  const result = await listWords({
    user: c.get('user'),
    ...parsed.data,
  })

  return c.json({
    data: result,
    meta: { requestId: c.get('requestId') },
  })
})

wordRoutes.get('/:wordId', async (c) => {
  const wordId = c.req.param('wordId')
  const word = await getWordById(c.get('user'), wordId)

  if (!word) {
    throw new AppError(404, 'WORD_NOT_FOUND', 'Word not found')
  }

  return c.json({
    data: word,
    meta: { requestId: c.get('requestId') },
  })
})
