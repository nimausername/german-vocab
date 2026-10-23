export type ApiErrorBody = {
  error: {
    code: string
    message: string
    details?: Array<{ field: string; reason: string }>
  }
  meta: {
    requestId: string
  }
}

export class AppError extends Error {
  readonly status: number
  readonly code: string
  readonly details?: Array<{ field: string; reason: string }>

  constructor(
    status: number,
    code: string,
    message: string,
    details?: Array<{ field: string; reason: string }>,
  ) {
    super(message)
    this.status = status
    this.code = code
    this.details = details
  }
}
