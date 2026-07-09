-- Required extensions
create extension if not exists pg_net;

-- Create trigger function to call Edge Function on order updates
create or replace function public.notify_order_status_change()
returns trigger
language plpgsql
as $$
declare
  url text := 'https://wzvlxfzhyudkoedllyha.functions.supabase.co/notify-order-status';
  headers jsonb := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind6dmx4ZnpoeXVka29lZGxseWhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyMjI0MzAsImV4cCI6MjA4Mzc5ODQzMH0.1uQDftqPMlplakoNkXqfqEaLewLBVAUwjwAX469_GE4'
  );
begin
  if (tg_op <> 'UPDATE') then
    return new;
  end if;

  -- Payment successful (payment_status => paid)
  if coalesce(old.payment_status, '') <> 'paid'
     and new.payment_status = 'paid' then
    perform net.http_post(
      url := url,
      headers := headers,
      body := jsonb_build_object(
        'event', 'payment_success',
        'user_id', new.user_id,
        'order_id', new.order_id,
        'store_id', new.store_id,
        'reference_number', new.reference_number,
        'status', new.status,
        'payment_status', new.payment_status,
        'total_amount', new.total_amount
      )
    );
  end if;

  -- Notify only on user-facing status changes.
  if coalesce(old.status, '') <> coalesce(new.status, '')
     and new.status in ('preparing', 'ready_for_pickup', 'completed') then
    perform net.http_post(
      url := url,
      headers := headers,
      body := jsonb_build_object(
        'event', 'order_status_changed',
        'user_id', new.user_id,
        'order_id', new.order_id,
        'store_id', new.store_id,
        'reference_number', new.reference_number,
        'status', new.status,
        'payment_status', new.payment_status,
        'total_amount', new.total_amount
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_orders_notify_status on public.orders;
create trigger trg_orders_notify_status
after update on public.orders
for each row
execute function public.notify_order_status_change();
