import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// -------------------- Types --------------------
type NotifyEvent =
  | "payment_success"
  | "order_confirmed"
  | "order_preparing"
  | "order_ready"
  | "order_status_changed";

type NotifyPayload = {
  user_id: number;
  order_id?: number;
  store_id?: number;
  reference_number?: string | null;
  status?: string | null;
  payment_status?: string | null;
  total_amount?: number | string | null;
  event: NotifyEvent;
};

// -------------------- Env --------------------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Put your downloaded service account JSON in this secret:
// supabase secrets set FCM_SERVICE_ACCOUNT="$(cat fcm-sa.json)"
// (PowerShell: "$(Get-Content -Raw .\\fcm-sa.json)")
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// -------------------- Supabase Client --------------------
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

// -------------------- Notification Copy --------------------
function formatAmount(value: unknown): string {
  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(amount)) return "0.00";
  return amount.toFixed(2);
}

function buildNotification(
  payload: NotifyPayload,
): { title: string; body: string } | null {
  const status = (payload.status ?? "").toString().trim().toLowerCase();
  const event = (payload.event ?? "").toString().trim().toLowerCase();

  if (event === "payment_success") {
    return {
      title: "Order Paid",
      body:
        `Your Order has been Paid and P ${formatAmount(payload.total_amount)} is spent.`,
    };
  }

  if (event === "order_preparing") {
    return {
      title: "Order Update",
      body: "Your Order is being Prepared",
    };
  }

  if (event === "order_ready") {
    return {
      title: "Order Update",
      body: "Your Order is ready for claiming.",
    };
  }

  if (
    event !== "order_status_changed" &&
    event !== "order_confirmed"
  ) {
    return null;
  }

  switch (status) {
    case "preparing":
      return {
        title: "Order Update",
        body: "Your Order is being Prepared",
      };
    case "ready_for_pickup":
      return {
        title: "Order Update",
        body: "Your Order is ready for claiming.",
      };
    case "completed":
      return {
        title: "Order Update",
        body: "Your Order is Complete! Please Leave a Review!!",
      };
    default:
      // Includes pending/pending_payment and all statuses that should stay silent.
      return null;
  }
}

// -------------------- FCM v1 Helpers --------------------
function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlEncodeString(str: string): string {
  return base64UrlEncodeBytes(new TextEncoder().encode(str));
}

async function importPkcs8PrivateKey(pem: string): Promise<CryptoKey> {
  const clean = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const der = Uint8Array.from(atob(clean), (c) => c.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function signJwtRS256(
  privateKeyPem: string,
  payload: Record<string, unknown>,
): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const encHeader = base64UrlEncodeString(JSON.stringify(header));
  const encPayload = base64UrlEncodeString(JSON.stringify(payload));
  const toSign = `${encHeader}.${encPayload}`;

  const key = await importPkcs8PrivateKey(privateKeyPem);
  const sigBuf = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(toSign),
  );

  const sig = base64UrlEncodeBytes(new Uint8Array(sigBuf));
  return `${toSign}.${sig}`;
}

async function getAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
  token_uri: string;
}) {
  const now = Math.floor(Date.now() / 1000);

  const assertion = await signJwtRS256(serviceAccount.private_key, {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri,
    iat: now,
    exp: now + 3600,
  });

  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  const res = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  if (!res.ok) {
    const t = await res.text();
    throw new Error(`OAuth token error: ${res.status} ${t}`);
  }

  const data = await res.json();
  return data.access_token as string;
}

async function sendFcmV1(
  projectId: string,
  accessToken: string,
  deviceToken: string,
  notification: { title: string; body: string },
  data: Record<string, string>,
) {
  const url =
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const payload = {
    message: {
      token: deviceToken,
      notification,
      data,
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`FCM v1 error: ${res.status} ${text}`);
  }

  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function isUnregisteredError(message: string) {
  const m = message.toLowerCase();
  return (
    m.includes("unregistered") ||
    m.includes("registration-token-not-registered") ||
    m.includes("requested entity was not found")
  );
}

// -------------------- Handler --------------------
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return json({ error: "Missing SUPABASE env" }, 500);
  }
  if (!FCM_SERVICE_ACCOUNT) {
    return json({ error: "Missing FCM_SERVICE_ACCOUNT env" }, 500);
  }

  let payload: NotifyPayload;
  try {
    payload = (await req.json()) as NotifyPayload;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  if (!payload?.user_id || !payload?.event) {
    return json({ error: "Missing user_id or event" }, 400);
  }

  const draft = buildNotification(payload);
  if (!draft) {
    return json({
      skipped: true,
      reason: "status_or_event_not_notifiable",
      event: payload.event,
      status: payload.status ?? null,
    });
  }

  // 1) Lookup tokens (newest first)
  const { data: tokens, error } = await supabase
    .from("user_push_tokens")
    .select("id, token, created_at, updated_at")
    .eq("user_id", payload.user_id)
    .eq("is_active", true)
    .order("updated_at", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) return json({ error: `Token lookup failed: ${error.message}` }, 500);

  const registrationIds = (tokens ?? [])
    .map((t: any) => t.token as string)
    .filter((t) => typeof t === "string" && t.length > 0);

  if (registrationIds.length === 0) return json({ sent: 0, results: [] });

  // 2) Parse service account (from secret)
  let sa: any;
  try {
    sa = JSON.parse(FCM_SERVICE_ACCOUNT);
  } catch {
    return json({ error: "FCM_SERVICE_ACCOUNT is not valid JSON" }, 500);
  }

  const projectId = sa?.project_id;
  const clientEmail = sa?.client_email;
  const privateKey = sa?.private_key;
  const tokenUri = sa?.token_uri;

  if (!projectId || !clientEmail || !privateKey || !tokenUri) {
    return json({ error: "FCM_SERVICE_ACCOUNT missing required fields" }, 500);
  }

  // 3) Create OAuth token
  let accessToken: string;
  try {
    accessToken = await getAccessToken({
      client_email: clientEmail,
      private_key: privateKey,
      token_uri: tokenUri,
    });
  } catch (e) {
    return json({ error: String(e?.message ?? e) }, 500);
  }

  // 4) Prepare notification + data
  const notif = {
    title: draft.title,
    body: draft.body,
  };

  const data: Record<string, string> = {
    event: payload.event,
    order_id: payload.order_id?.toString() ?? "",
    store_id: payload.store_id?.toString() ?? "",
    reference_number: payload.reference_number ?? "",
    status: payload.status ?? "",
    payment_status: payload.payment_status ?? "",
    total_amount: payload.total_amount?.toString() ?? "",
  };

  // 5) Send to all active tokens.
  const results: Array<{
    token: string;
    ok: boolean;
    res?: unknown;
    error?: string;
  }> = [];

  let sent = 0;
  for (const token of registrationIds) {
    try {
      const res = await sendFcmV1(projectId, accessToken, token, notif, data);
      results.push({ token, ok: true, res });
      sent += 1;
    } catch (e) {
      const errorMsg = String(e?.message ?? e);
      results.push({ token, ok: false, error: errorMsg });

      if (isUnregisteredError(errorMsg)) {
        await supabase
          .from("user_push_tokens")
          .update({ is_active: false })
          .eq("user_id", payload.user_id)
          .eq("token", token);
      }
    }
  }

  return json({ sent, total: registrationIds.length, results });
});
