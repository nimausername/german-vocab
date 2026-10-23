import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { HTTPException } from 'hono/http-exception'
import { randomUUID } from 'node:crypto'
import { ZodError } from 'zod'
import { config } from './config.js'
import { AppError } from './lib/errors.js'
import { authRoutes } from './routes/auth.js'
import { planRoutes } from './routes/plans.js'
import { reviewRoutes } from './routes/reviews.js'
import { statsRoutes } from './routes/stats.js'

type AppVariables = {
  requestId: string
}

const app = new Hono<{ Variables: AppVariables }>()

app.use('*', async (c, next) => {
  const requestId = c.req.header('x-request-id') ?? randomUUID()
  c.set('requestId', requestId)
  c.header('X-Request-Id', requestId)
  await next()
})

app.use(
  '*',
  cors({
    origin: config.CORS_ORIGIN === '*' ? '*' : config.CORS_ORIGIN.split(','),
    allowHeaders: ['Authorization', 'Content-Type', 'X-Request-Id'],
  }),
)

app.get('/health', (c) =>
  c.json({
    data: { status: 'ok' },
    meta: { requestId: c.get('requestId') },
  }),
)

app.route('/v1/auth', authRoutes)
app.route('/v1/plans', planRoutes)
app.route('/v1/reviews', reviewRoutes)
app.route('/v1/stats', statsRoutes)

app.onError((error, c) => {
  const requestId = c.get('requestId') ?? randomUUID()

  if (error instanceof AppError) {
    return c.json(
      {
        error: {
          code: error.code,
          message: error.message,
          details: error.details,
        },
        meta: { requestId },
      },
      error.status as 400,
    )
  }

  if (error instanceof ZodError) {
    return c.json(
      {
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Invalid request body',
          details: error.issues.map((issue) => ({
            field: issue.path.join('.') || 'body',
            reason: issue.message,
          })),
        },
        meta: { requestId },
      },
      400,
    )
  }

  if (error instanceof HTTPException) {
    return c.json(
      {
        error: {
          code: 'HTTP_ERROR',
          message: error.message,
        },
        meta: { requestId },
      },
      error.status,
    )
  }

  console.error(error)
  return c.json(
    {
      error: {
        code: 'INTERNAL_ERROR',
        message: 'Unexpected server error',
      },
      meta: { requestId },
    },
    500,
  )
})

serve({ fetch: app.fetch, port: config.PORT, hostname: config.HOST }, (info) => {
  console.log(`German Vocab API listening on http://${config.HOST}:${info.port}`)
})
