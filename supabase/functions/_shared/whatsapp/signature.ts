const encoder = new TextEncoder();

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export function constantTimeEqual(left: string, right: string): boolean {
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  const size = Math.max(a.length, b.length);
  let difference = a.length ^ b.length;
  for (let index = 0; index < size; index += 1) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}

export async function sha256Hex(rawBody: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", rawBody);
  return bytesToHex(new Uint8Array(digest));
}

export async function calculateMetaSignature(rawBody: Uint8Array, appSecret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, rawBody);
  return `sha256=${bytesToHex(new Uint8Array(signature))}`;
}

export async function verifyMetaSignature(
  rawBody: Uint8Array,
  suppliedSignature: string | null,
  appSecret: string,
): Promise<boolean> {
  if (!suppliedSignature || !appSecret) return false;
  const expected = await calculateMetaSignature(rawBody, appSecret);
  return constantTimeEqual(suppliedSignature.trim().toLowerCase(), expected);
}
