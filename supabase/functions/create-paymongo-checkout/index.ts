// supabase/functions/create-paymongo-checkout/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ReqBody = { orderId: number };

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

function toCentavos(amountPhp: number) {
  return Math.round(Number(amountPhp) * 100);
}

function normalizePHPhone(phone?: string | null): string | undefined {
  if (!phone) return undefined;
  let p = phone.trim().replace(/[\s-]/g, "");
  if (p.startsWith("+")) p = p.slice(1);
  if (p.startsWith("63")) p = p.slice(2);
  if (p.startsWith("0")) p = p.slice(1);
  // PayMongo UI already prefixes +63, so send 9XXXXXXXXX only
  if (/^9\d{9}$/.test(p)) return p;
  return undefined;
}

function buildRedirectUrl(base: string, params: Record<string, string>) {
  const u = new URL(base);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  return u.toString();
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return json({ ok: true }, 200);
    if (req.method !== "POST") return json({ error: "POST only" }, 405);

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const PAYMONGO_SK = Deno.env.get("PAYMONGO_SECRET_KEY");

    // ✅ Put these in Supabase Secrets (or it will use the sane defaults below):
    // PAYMONGO_SUCCESS_URL = https://wzvlxfzhyudkoedllyha.supabase.co/functions/v1/paymongo-success
    // PAYMONGO_CANCEL_URL  = https://wzvlxfzhyudkoedllyha.supabase.co/functions/v1/paymongo-cancel
    const SUCCESS_URL_BASE =
      Deno.env.get("PAYMONGO_SUCCESS_URL") ??
      "https://wzvlxfzhyudkoedllyha.supabase.co/functions/v1/paymongo-success";
    const CANCEL_URL_BASE =
      Deno.env.get("PAYMONGO_CANCEL_URL") ??
      "https://wzvlxfzhyudkoedllyha.supabase.co/functions/v1/paymongo-cancel";

    if (!SUPABASE_URL || !SERVICE_KEY) {
      return json({ error: "Missing SUPABASE env vars" }, 500);
    }
    if (!PAYMONGO_SK) {
      return json({ error: "Missing PAYMONGO_SECRET_KEY secret" }, 500);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

    const body = (await req.json().catch(() => null)) as ReqBody | null;
    const orderId = Number(body?.orderId);
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return json({ error: "Missing/invalid orderId" }, 400);
    }

    // ✅ DISAMBIGUATED relationship: orders.user_id -> users.user_id
    const { data: order, error: orderErr } = await supabase
      .from("orders")
      .select(
        `
        order_id,
        reference_number,
        total_amount,
        payment_status,
        paymongo_checkout_session_id,
        paymongo_checkout_url,
        user_id,
        voucher_id,
        users!orders_user_id_fkey (
          first_name,
          last_name,
          user_email,
          contact_number,
          auth_user_id,
          street,
          barangay,
          city,
          province
        )
      `,
      )
      .eq("order_id", orderId)
      .single();

    if (orderErr || !order) {
      return json({ error: orderErr?.message ?? "Order not found" }, 404);
    }

    // ✅ Build the redirect URLs (so the page can show "You can close this window")
    // We attach order_id + reference_number for nicer display.
    const ref = String(order.reference_number ?? "").trim();

    const successUrl = buildRedirectUrl(SUCCESS_URL_BASE, {
      order_id: String(order.order_id),
      ...(ref ? { reference_number: ref } : {}),
    });

    const cancelUrl = buildRedirectUrl(CANCEL_URL_BASE, {
      order_id: String(order.order_id),
      ...(ref ? { reference_number: ref } : {}),
    });

    // ✅ Reuse existing checkout if present
    if (order.paymongo_checkout_session_id && order.paymongo_checkout_url) {
      if (order.payment_status !== "pending" && order.payment_status !== "paid") {
        await supabase
          .from("orders")
          .update({ payment_status: "pending" })
          .eq("order_id", orderId);
      }

      return json({
        orderId,
        checkoutSessionId: order.paymongo_checkout_session_id,
        checkoutUrl: order.paymongo_checkout_url,
        successUrl,
        cancelUrl,
        reused: true,
      });
    }

    const { data: items, error: itemsErr } = await supabase
      .from("order_items")
      .select(
        "order_item_id, menu_id, quantity, unit_price, is_free_item, store_menu_items(name, category_id)",
      )
      .eq("order_id", orderId);

    if (itemsErr) return json({ error: itemsErr.message }, 500);

    const orderItems = items ?? [];

    const orderItemIds = orderItems
      .map((i: any) => Number(i.order_item_id))
      .filter((id: number) => Number.isFinite(id) && id > 0);

    const { data: addonRows, error: addonErr } = orderItemIds.length
      ? await supabase
          .from("order_item_addons")
          .select("order_item_id, addon_menu_id, quantity, unit_price")
          .in("order_item_id", orderItemIds)
      : { data: [], error: null };

    if (addonErr) return json({ error: addonErr.message }, 500);

    const addonMenuIds = (addonRows ?? [])
      .map((r: any) => Number(r.addon_menu_id))
      .filter((id: number) => Number.isFinite(id) && id > 0);

    const { data: addonMenus, error: addonMenuErr } = addonMenuIds.length
      ? await supabase
          .from("store_menu_items")
          .select("menu_id, name")
          .in("menu_id", addonMenuIds)
      : { data: [], error: null };

    if (addonMenuErr) return json({ error: addonMenuErr.message }, 500);

    const addonNameById = new Map<number, string>();
    for (const m of addonMenus ?? []) {
      addonNameById.set(Number(m.menu_id), String(m.name ?? "Add-on"));
    }

    const addonsByOrderItemId = new Map<number, any[]>();
    for (const r of addonRows ?? []) {
      const orderItemId = Number(r.order_item_id);
      if (!addonsByOrderItemId.has(orderItemId)) {
        addonsByOrderItemId.set(orderItemId, []);
      }
      addonsByOrderItemId.get(orderItemId)!.push(r);
    }

    const voucherId = (order as any).voucher_id as number | null;
    let voucher: any = null;

    if (voucherId) {
      const { data: v, error: vErr } = await supabase
        .from("store_vouchers")
        .select(
          `
          voucher_id, code, voucher_type,
          buy_menu_id, free_menu_id,
          store_voucher_targets(target_type, category_id, menu_id),
          store_voucher_bogo_rules(
            rule_id, buy_type, buy_menu_id, buy_category_id, buy_qty,
            get_type, get_menu_id, get_category_id, get_qty, get_discount_percent
          )
        `,
        )
        .eq("voucher_id", voucherId)
        .maybeSingle();
      if (vErr) return json({ error: vErr.message }, 500);
      voucher = v;
    }

    function isEligible(item: any) {
      if (!voucher) return false;
      const menuId = Number(item.menu_id);
      const categoryId = Number(item.store_menu_items?.category_id ?? 0) || null;
      const voucherType = String(voucher.voucher_type ?? "");

      if (voucherType === "discount") {
        const targets = voucher.store_voucher_targets ?? [];
        if (!targets.length) return true;
        if (targets.some((t: any) => t.target_type === "all_items")) return true;
        return targets.some((t: any) => {
          if (t.target_type === "menu_item")
            return Number(t.menu_id) === menuId;
          if (t.target_type === "category")
            return Number(t.category_id) === categoryId;
          return false;
        });
      }

      if (voucherType === "b1t1") {
        return (
          Number(voucher.buy_menu_id) === menuId ||
          Number(voucher.free_menu_id) === menuId
        );
      }

      if (voucherType === "bogo") {
        const rules = voucher.store_voucher_bogo_rules ?? [];
        return rules.some((r: any) => {
          if (r.buy_type === "menu_item" && Number(r.buy_menu_id) === menuId)
            return true;
          if (r.buy_type === "category" && Number(r.buy_category_id) === categoryId)
            return true;
          if (r.get_type === "menu_item" && Number(r.get_menu_id) === menuId)
            return true;
          if (r.get_type === "category" && Number(r.get_category_id) === categoryId)
            return true;
          return false;
        });
      }

      return false;
    }

    const line_items = orderItems
      .filter((i: any) => !i.is_free_item)
      .flatMap((i: any) => {
        const eligible = isEligible(i);
        const voucherCode = voucher?.code ? String(voucher.code) : "";
        const base = {
          currency: "PHP",
          amount: toCentavos(Number(i.unit_price)),
          name:
            i.store_menu_items?.name && eligible && voucherCode
              ? `${i.store_menu_items?.name} • Voucher ${voucherCode}`
              : i.store_menu_items?.name ?? "Item",
          quantity: Number(i.quantity) || 1,
          description: `Order ${order.reference_number}${
            eligible && voucherCode ? ` • Voucher ${voucherCode}` : ""
          }`,
        };

        const addons = (addonsByOrderItemId.get(Number(i.order_item_id)) ?? []).map(
          (a: any) => ({
            currency: "PHP",
            amount: toCentavos(Number(a.unit_price)),
            name: addonNameById.get(Number(a.addon_menu_id)) ?? "Add-on",
            quantity: Number(a.quantity) || 1,
            description: `Add-on for ${i.store_menu_items?.name ?? "Item"}`,
          }),
        );

        return [base, ...addons];
      });

    if (!line_items.length) {
      return json({ error: "No billable line items found." }, 400);
    }

    const u = (order as any).users ?? null;
    let customerEmail =
      u && typeof u.user_email === "string" ? u.user_email.trim() : "";
    const authUserId =
      u && typeof u.auth_user_id === "string" ? u.auth_user_id : null;

    if (!customerEmail && authUserId) {
      const { data: authUser } = await supabase.auth.admin.getUserById(
        authUserId,
      );
      customerEmail = (authUser?.user?.email ?? "").trim();
    }

    const customerName =
      u && (u.first_name || u.last_name)
        ? `${u.first_name ?? ""} ${u.last_name ?? ""}`.trim()
        : "Siply Customer";
    const customerPhone = normalizePHPhone(u?.contact_number ?? null);
    const street = (u?.street ?? "").toString().trim();
    const barangay = (u?.barangay ?? "").toString().trim();
    const city = (u?.city ?? "").toString().trim();
    const province = (u?.province ?? "").toString().trim();
    const line1 = [street, barangay].filter(Boolean).join(", ").trim();

    if (!customerEmail || !customerPhone) {
      return json(
        {
          error:
            "Missing customer details. Please update your email and contact number in your profile.",
          details: {
            emailPresent: Boolean(customerEmail),
            phonePresent: Boolean(customerPhone),
          },
        },
        400,
      );
    }

    const customer = {
      name: customerName,
      email: customerEmail,
      phone: customerPhone,
    };

    const billing = {
      name: customerName,
      email: customerEmail,
      phone: customerPhone,
      address: {
        line1: line1 || undefined,
        city: city || undefined,
        state: province || undefined,
        country: "PH",
      },
    };

    const auth = "Basic " + btoa(`${PAYMONGO_SK}:`);

    const pmRes = await fetch("https://api.paymongo.com/v1/checkout_sessions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: auth,
      },
      body: JSON.stringify({
        data: {
          attributes: {
            line_items,
            payment_method_types: ["qrph"],
            // ✅ IMPORTANT: Use our edge functions (not example.com)
            success_url: successUrl,
            cancel_url: cancelUrl,
            description: `Siply Order ${order.reference_number}`,
            ...(customer ? { customer } : {}),
            billing,
            metadata: {
              order_id: String(order.order_id),
              reference_number: order.reference_number,
            },
          },
        },
      }),
    });

    const pmJson = await pmRes.json().catch(() => ({}));
    console.log("PayMongo checkout response:", {
      ok: pmRes.ok,
      status: pmRes.status,
      statusText: pmRes.statusText,
      body: pmJson,
    });

    if (!pmRes.ok) {
      await supabase
        .from("orders")
        .update({
          payment_status: "failed",
          payment_error: JSON.stringify(pmJson),
        })
        .eq("order_id", orderId);

      await supabase.from("payments").upsert(
        {
          order_id: orderId,
          provider: "paymongo",
          payment_method: "qrph",
          status: "failed",
          amount: Number(order.total_amount),
          currency: "PHP",
          failure_message: JSON.stringify(pmJson),
          raw_event: pmJson,
        },
        { onConflict: "order_id" },
      );

      return json({ error: "PayMongo error", details: pmJson }, 502);
    }

    const checkoutSessionId = pmJson?.data?.id as string | undefined;
    const checkoutUrl = pmJson?.data?.attributes?.checkout_url as
      | string
      | undefined;

    if (!checkoutSessionId || !checkoutUrl) {
      return json({ error: "Missing checkout session id/url", raw: pmJson }, 502);
    }

    await supabase
      .from("orders")
      .update({
        payment_provider: "paymongo",
        payment_method: "qrph",
        payment_status: "pending",
        paymongo_checkout_session_id: checkoutSessionId,
        paymongo_checkout_url: checkoutUrl,
        status: "pending_payment",
        payment_error: null,
      })
      .eq("order_id", orderId);

    await supabase.from("payments").upsert(
      {
        order_id: orderId,
        provider: "paymongo",
        payment_method: "qrph",
        provider_checkout_session_id: checkoutSessionId,
        checkout_url: checkoutUrl,
        status: "pending",
        amount: Number(order.total_amount),
        currency: "PHP",
      },
      { onConflict: "order_id" },
    );

    return json({
      orderId,
      checkoutSessionId,
      checkoutUrl,
      successUrl,
      cancelUrl,
      reused: false,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
