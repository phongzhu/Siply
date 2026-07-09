function htmlPage(opts: {
  title: string;
  heading: string;
  message: string;
  badge?: string;
  status?: "success" | "cancel";
}) {
  const color = opts.status === "success" ? "#16a34a" : "#ef4444";
  const badgeBg = opts.status === "success" ? "#dcfce7" : "#fee2e2";
  const badgeText = opts.status === "success" ? "#166534" : "#991b1b";

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>${opts.title}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <style>
    body{margin:0;font-family:Arial,system-ui,-apple-system,Segoe UI,Roboto;background:#f7f7fb;display:flex;align-items:center;justify-content:center;height:100vh;padding:18px}
    .card{background:#fff;width:420px;max-width:100%;padding:26px;border-radius:16px;box-shadow:0 10px 30px rgba(0,0,0,.08);text-align:center}
    h1{margin:0 0 10px;font-size:22px;color:${color}}
    p{margin:0;color:#334155;line-height:1.5}
    .muted{margin-top:8px;color:#64748b;font-size:13px}
    .badge{display:inline-block;margin-top:14px;padding:7px 10px;border-radius:999px;background:${badgeBg};color:${badgeText};font-size:12px;font-weight:700}
    .actions{margin-top:18px;display:flex;gap:10px;justify-content:center;flex-wrap:wrap}
    button{padding:12px 14px;border:0;border-radius:12px;background:#1e88e5;color:#fff;font-size:14px;cursor:pointer}
    .hint{margin-top:14px;font-size:12px;color:#94a3b8}
  </style>
</head>
<body>
  <div class="card">
    <h1>${opts.heading}</h1>
    <p>${opts.message}</p>
    ${opts.badge ? `<div class="badge">${opts.badge}</div>` : ""}
    <div class="actions">
      <button onclick="tryClose()">Close window</button>
    </div>
    <div class="hint">You can safely close this tab.</div>
  </div>

  <script>
    function tryClose(){
      window.close();
      setTimeout(() => alert("You can now close this tab."), 150);
    }
  </script>
</body>
</html>`;
}

export default async (req: Request) => {
  const url = new URL(req.url);
  const orderId = url.searchParams.get("order_id") ?? "";
  const ref = url.searchParams.get("reference_number") ?? "";

  const badge =
    orderId && ref
      ? `Order #${orderId} | ${ref}`
      : orderId
      ? `Order #${orderId}`
      : ref
      ? ref
      : undefined;

  const page = htmlPage({
    title: "Payment cancelled",
    heading: "Payment cancelled",
    message:
      "No worries. Your payment was not completed. You may close this window and try again.",
    badge,
    status: "cancel",
  });

  return new Response(page, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
};
