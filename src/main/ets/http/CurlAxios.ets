import curlHttp from 'libcurl_http.so'

export type CurlHeaderValue = string | number | boolean
export type CurlHeaders = Record<string, CurlHeaderValue>
export type CurlParams = Record<string, Object>

export interface CurlAxiosRequestConfig {
  url?: string
  method?: string
  baseURL?: string
  headers?: CurlHeaders
  params?: Object
  data?: Object | string | number | boolean | null
  timeout?: number
  connectTimeout?: number
  readTimeout?: number
  maxRedirects?: number
  insecure?: boolean
  proxy?: boolean | Object
  usingProtocol?: number
  retry?: number
  retryDelay?: number
  authRetry?: number
  __retryCount?: number
  __authRetryCount?: number
}

export interface CurlAxiosResponse<T = Object> {
  data: T
  status: number
  statusText: string
  headers: Record<string, string>
  config: CurlAxiosRequestConfig
  requestUrl: string
  performanceTiming?: Record<string, number>
}

interface NativeCurlResponse {
  status: number
  body: string
  headers: Record<string, string>
  effectiveUrl: string
}

interface NativeCurlError extends Error {
  code?: string
  curlCode?: number
}

export type CurlInterceptorResult = Object | string | number | boolean | null | undefined
type Fulfilled<T, R> = (value: T) => R | Promise<R>
type Rejected<R> = (error: CurlAxiosError) => R | Promise<R>

interface InterceptorHandler<T, R> {
  fulfilled: Fulfilled<T, R>
  rejected?: Rejected<R>
}

export class CurlAxiosError<T = Object> extends Error {
  code: string
  config?: CurlAxiosRequestConfig
  response?: CurlAxiosResponse<T>
  curlCode?: number
  status?: number

  constructor(message: string, code: string, config?: CurlAxiosRequestConfig,
    response?: CurlAxiosResponse<T>, curlCode?: number) {
    super(message)
    this.name = 'CurlAxiosError'
    this.code = code
    this.config = config
    this.response = response
    this.curlCode = curlCode
    this.status = response?.status
  }
}

export class CurlInterceptorManager<T, R> {
  private handlers: Array<InterceptorHandler<T, R> | undefined> = []

  use(fulfilled: Fulfilled<T, R>, rejected?: Rejected<R>): number {
    this.handlers.push({ fulfilled, rejected })
    return this.handlers.length - 1
  }

  eject(identifier: number): void {
    if (identifier >= 0 && identifier < this.handlers.length) {
      this.handlers[identifier] = undefined
    }
  }

  clear(): void {
    this.handlers = []
  }

  getHandlers(): Array<InterceptorHandler<T, R> | undefined> {
    return this.handlers
  }
}

function copyHeaders(source?: CurlHeaders): CurlHeaders {
  const result: CurlHeaders = {}
  if (!source) {
    return result
  }
  Object.keys(source).forEach((key: string) => {
    result[key] = source[key]
  })
  return result
}

function mergeHeaders(defaults?: CurlHeaders, request?: CurlHeaders): CurlHeaders {
  const result = copyHeaders(defaults)
  if (request) {
    Object.keys(request).forEach((key: string) => {
      result[key] = request[key]
    })
  }
  return result
}

function mergeConfig(defaults: CurlAxiosRequestConfig, request: CurlAxiosRequestConfig): CurlAxiosRequestConfig {
  return {
    url: request.url,
    method: request.method || defaults.method,
    baseURL: request.baseURL !== undefined ? request.baseURL : defaults.baseURL,
    headers: mergeHeaders(defaults.headers, request.headers),
    params: request.params,
    data: request.data,
    timeout: request.timeout !== undefined ? request.timeout : defaults.timeout,
    connectTimeout: request.connectTimeout !== undefined ? request.connectTimeout : defaults.connectTimeout,
    readTimeout: request.readTimeout !== undefined ? request.readTimeout : defaults.readTimeout,
    maxRedirects: request.maxRedirects !== undefined ? request.maxRedirects : defaults.maxRedirects,
    insecure: request.insecure !== undefined ? request.insecure : defaults.insecure,
    proxy: request.proxy !== undefined ? request.proxy : defaults.proxy,
    usingProtocol: request.usingProtocol !== undefined ? request.usingProtocol : defaults.usingProtocol,
    retry: request.retry !== undefined ? request.retry : defaults.retry,
    retryDelay: request.retryDelay !== undefined ? request.retryDelay : defaults.retryDelay,
    authRetry: request.authRetry !== undefined ? request.authRetry : defaults.authRetry,
    __retryCount: request.__retryCount,
    __authRetryCount: request.__authRetryCount
  }
}

function isAbsoluteUrl(url: string): boolean {
  const lowerUrl = url.toLowerCase()
  return lowerUrl.startsWith('http://') || lowerUrl.startsWith('https://')
}

function combineUrl(baseURL: string, url: string): string {
  if (!baseURL || isAbsoluteUrl(url)) {
    return url
  }
  const normalizedBase = baseURL.endsWith('/') ? baseURL.substring(0, baseURL.length - 1) : baseURL
  const normalizedPath = url.startsWith('/') ? url : '/' + url
  return normalizedBase + normalizedPath
}

function appendQuery(url: string, params?: Object): string {
  if (!params) {
    return url
  }
  const values = params as CurlParams
  const parts: string[] = []
  Object.keys(values).forEach((key: string) => {
    const value = values[key]
    if (value === undefined || value === null) {
      return
    }
    if (Array.isArray(value)) {
      value.forEach((item: Object) => {
        parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(item.toString()))
      })
    } else {
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(value.toString()))
    }
  })
  if (parts.length === 0) {
    return url
  }
  return url + (url.indexOf('?') >= 0 ? '&' : '?') + parts.join('&')
}

function hasHeader(headers: CurlHeaders, expectedName: string): boolean {
  const lowerName = expectedName.toLowerCase()
  return Object.keys(headers).some((name: string) => name.toLowerCase() === lowerName)
}

function normalizeHeaders(headers: CurlHeaders): Record<string, string> {
  const result: Record<string, string> = {}
  Object.keys(headers).forEach((name: string) => {
    result[name] = headers[name].toString()
  })
  return result
}

function serializeBody(config: CurlAxiosRequestConfig): string | undefined {
  if (config.data === undefined || config.data === null) {
    return undefined
  }
  if (typeof config.data === 'string') {
    return config.data
  }
  return JSON.stringify(config.data)
}

function parseResponseBody(body: string): Object | string {
  if (!body) {
    return ''
  }
  try {
    return JSON.parse(body) as Object
  } catch (_) {
    return body
  }
}

function getStatusText(status: number): string {
  if (status >= 200 && status < 300) {
    return 'OK'
  }
  return 'HTTP ' + status
}

export class CurlAxiosInstance {
  readonly interceptors = {
    request: new CurlInterceptorManager<CurlAxiosRequestConfig, CurlAxiosRequestConfig>(),
    response: new CurlInterceptorManager<CurlAxiosResponse, CurlInterceptorResult>()
  }

  constructor(private defaults: CurlAxiosRequestConfig = {}) {
  }

  async request<T = Object>(requestConfig: CurlAxiosRequestConfig): Promise<T> {
    let config = mergeConfig(this.defaults, requestConfig)
    const requestHandlers = this.interceptors.request.getHandlers()
    for (let index = requestHandlers.length - 1; index >= 0; index--) {
      const handler = requestHandlers[index]
      if (!handler) {
        continue
      }
      try {
        config = await handler.fulfilled(config)
      } catch (reason) {
        if (!handler.rejected) {
          throw reason
        }
        config = await handler.rejected(this.toError(reason, config))
      }
    }

    const url = appendQuery(combineUrl(config.baseURL || '', config.url || ''), config.params)
    const method = (config.method || 'GET').toUpperCase()
    const headers = copyHeaders(config.headers)
    const body = serializeBody(config)
    if (body !== undefined && !hasHeader(headers, 'Content-Type')) {
      headers['Content-Type'] = 'application/json'
    }
    if (!hasHeader(headers, 'Accept')) {
      headers['Accept'] = 'application/json, text/plain, */*'
    }

    try {
      const totalTimeout = config.timeout || config.readTimeout || 10000
      const nativeResponse = await curlHttp.request({
        url,
        method,
        headers: normalizeHeaders(headers),
        body,
        connectTimeoutMs: config.connectTimeout || totalTimeout,
        timeoutMs: totalTimeout,
        followRedirects: config.maxRedirects !== 0,
        insecure: config.insecure || false
      }) as NativeCurlResponse
      const response: CurlAxiosResponse = {
        data: parseResponseBody(nativeResponse.body),
        status: nativeResponse.status,
        statusText: getStatusText(nativeResponse.status),
        headers: nativeResponse.headers,
        config,
        requestUrl: nativeResponse.effectiveUrl || url
      }
      if (response.status < 200 || response.status >= 300) {
        throw new CurlAxiosError('Request failed with status code ' + response.status,
          'ERR_BAD_RESPONSE', config, response)
      }
      return await this.applyResponseInterceptors(response) as T
    } catch (reason) {
      const error = this.toError(reason, config)
      return await this.applyResponseErrorInterceptors(error) as T
    }
  }

  get<T = Object>(url: string, config: CurlAxiosRequestConfig = {}): Promise<T> {
    config.url = url
    config.method = 'GET'
    return this.request<T>(config)
  }

  post<T = Object>(url: string, data?: Object | string | number | boolean | null,
    config: CurlAxiosRequestConfig = {}): Promise<T> {
    config.url = url
    config.method = 'POST'
    config.data = data
    return this.request<T>(config)
  }

  put<T = Object>(url: string, data?: Object | string | number | boolean | null,
    config: CurlAxiosRequestConfig = {}): Promise<T> {
    config.url = url
    config.method = 'PUT'
    config.data = data
    return this.request<T>(config)
  }

  delete<T = Object>(url: string, config: CurlAxiosRequestConfig = {}): Promise<T> {
    config.url = url
    config.method = 'DELETE'
    return this.request<T>(config)
  }

  private async applyResponseInterceptors(response: CurlAxiosResponse): Promise<CurlInterceptorResult> {
    let current: CurlInterceptorResult = response
    const handlers = this.interceptors.response.getHandlers()
    for (let index = 0; index < handlers.length; index++) {
      const handler = handlers[index]
      if (handler) {
        current = await handler.fulfilled(current as CurlAxiosResponse)
      }
    }
    return current
  }

  private async applyResponseErrorInterceptors(error: CurlAxiosError): Promise<CurlInterceptorResult> {
    let current = error
    const handlers = this.interceptors.response.getHandlers()
    for (let index = 0; index < handlers.length; index++) {
      const handler = handlers[index]
      if (!handler || !handler.rejected) {
        continue
      }
      try {
        return await handler.rejected(current)
      } catch (reason) {
        current = this.toError(reason, current.config)
      }
    }
    throw current
  }

  private toError(reason: Object, config?: CurlAxiosRequestConfig): CurlAxiosError {
    if (reason instanceof CurlAxiosError) {
      if (!reason.config) {
        reason.config = config
      }
      return reason
    }
    const nativeError = reason as NativeCurlError
    const message = nativeError.message || reason.toString()
    return new CurlAxiosError(message, nativeError.code || 'ERR_NETWORK', config,
      undefined, nativeError.curlCode)
  }
}

export class CurlAxios {
  static create(defaults: CurlAxiosRequestConfig = {}): CurlAxiosInstance {
    return new CurlAxiosInstance(defaults)
  }
}
