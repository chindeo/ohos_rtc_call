export interface NativeCurlRequestOptions {
  url: string
  method: string
  headers: Record<string, string>
  body?: string
  connectTimeoutMs: number
  timeoutMs: number
  followRedirects: boolean
  insecure: boolean
}

export interface NativeCurlResponse {
  status: number
  body: string
  headers: Record<string, string>
  effectiveUrl: string
}

export function request(options: NativeCurlRequestOptions): Promise<NativeCurlResponse>
