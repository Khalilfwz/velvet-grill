ALTER TABLE public.orders
  ALTER COLUMN payment_status
  SET DEFAULT 'UNPAID'::public.payment_status;
