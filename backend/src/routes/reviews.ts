import { Hono } from 'hono'
import { z } from 'zod'
import type { AuthVariables } from '../middleware/auth.js'
import { requireAuth } from '../middleware/auth.js'
import { submitReview } from '../services/review-service.js'

const reviewSchema = z.object({
  cardId: z.string().uuid(),
  rating: z.number().int().min(1).max(4),
  durationMs: z.number().int().nonnegative().optional(),
})

export const reviewRoutes = new Hono<{ Variables: AuthVariables }>()

reviewRoutes.use('*', requireAuth)

reviewRoutes.post('/', async (c) => {
  const body = reviewSchema.parse(await c.req.json())
  const result = await submitReview({
    user: c.get('user'),
    cardId: body.cardId,
    rating: body.rating,
    durationMs: body.durationMs,
  })

  return c.json({
    data: result,
    meta: { requestId: c.get('requestId') },
  })
})
