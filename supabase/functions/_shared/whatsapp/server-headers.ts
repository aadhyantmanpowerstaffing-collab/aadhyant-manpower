/** Secret keys are API keys, not JWTs. Never return these headers to a browser. */
export function serverDatabaseHeaders(key: string): Record<string, string> {
  if (!key || /\s/.test(key) || key.startsWith("sb_publishable_")) {
    throw new Error("Server database credential configuration is invalid");
  }
  const headers: Record<string, string> = { apikey: key };
  if (!key.startsWith("sb_secret_")) headers.authorization = `Bearer ${key}`;
  return headers;
}

export function runtimeServerKey(get: (name: string) => string): string {
  const explicit = get("SUPABASE_SECRET_KEY");
  if (explicit) return explicit;
  const injected = get("SUPABASE_SECRET_KEYS");
  if (injected) {
    try {
      const keys: unknown = JSON.parse(injected);
      if (keys && typeof keys === "object" && typeof (keys as Record<string, unknown>).default === "string") {
        return (keys as Record<string, string>).default;
      }
    } catch { /* Never log the injected dictionary. */ }
    throw new Error("Server database credential configuration is invalid");
  }
  return get("SUPABASE_SERVICE_ROLE_KEY");
}

