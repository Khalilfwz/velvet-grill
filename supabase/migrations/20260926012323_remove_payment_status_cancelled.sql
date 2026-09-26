create type public.payment_status_new as enum (
  'UNPAID',
  'PENDING',
  'PAID',
  'FAILED',
  'EXPIRED',
  'REFUNDED'
);

alter table public.orders
  alter column payment_status drop default;

alter table public.payments
  alter column status drop default;

alter table public.orders
  alter column payment_status
  type public.payment_status_new
  using payment_status::text::public.payment_status_new;

alter table public.payments
  alter column status
  type public.payment_status_new
  using status::text::public.payment_status_new;

drop type public.payment_status;

alter type public.payment_status_new
  rename to payment_status;

alter table public.orders
  alter column payment_status
  set default 'UNPAID'::public.payment_status;

alter table public.payments
  alter column status
  set default 'PENDING'::public.payment_status;
