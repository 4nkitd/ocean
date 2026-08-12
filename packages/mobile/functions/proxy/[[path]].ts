/**
 * Same-origin proxy for the mobile client.
 *
 * The client talks to `opencode serve` over the network, and not every
 * deployment answers cross-origin requests: some reverse proxies strip CORS
 * headers, and Caddy's `basic_auth` answers the preflight with a 401. Rather
 * than asking the operator to reconfigure the server, this function runs on the
 * app's own origin and forwards every request server-side, so the browser only
 * ever makes same-origin calls. The target server is the first path segment,
 * URL-encoded, so no header surgery or config is needed on the server.
 *
 *   /proxy/https%3A%2F%2Fdm.4nkitd.in/path?query → fetch https://dm.4nkitd.in/path?query
 *
 * Everything — method, body, auth header, and the SSE response stream — is
 * passed through untouched.
 */
export async function onRequest(context: {
  request: Request
  params: Record<string, string | string[] | undefined>
}): Promise<Response> {
  const request = context.request
  const url = new URL(request.url)
  const rest = url.pathname.replace(/^\/proxy\//, "")

  const slash = rest.indexOf("/")
  const encodedTarget = slash === -1 ? rest : rest.slice(0, slash)
  const suffix = slash === -1 ? "" : rest.slice(slash)

  let target: string
  try {
    target = decodeURIComponent(encodedTarget)
  } catch {
    return new Response("Bad target", { status: 400 })
  }
  if (!/^https?:\/\/.+/i.test(target)) {
    return new Response("Target must be an http(s) URL", { status: 400 })
  }

  const upstream = new URL(`${target.replace(/\/+$/, "")}${suffix}${url.search}`)

  const headers = new Headers(request.headers)
  // Host must be the target's own, or the server may reject the request.
  headers.delete("host")
  headers.set("x-forwarded-host", url.host)

  return fetch(upstream.toString(), {
    method: request.method,
    headers,
    body: request.method === "GET" || request.method === "HEAD" ? undefined : request.body,
    redirect: "manual",
  })
}
