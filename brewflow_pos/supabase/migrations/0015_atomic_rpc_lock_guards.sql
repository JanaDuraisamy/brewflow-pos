-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0015: Atomic RPC Lock/Statement Guards
--
-- Fix: the atomic RPCs from 0011/0012 and their sequence helpers take FOR
-- UPDATE row locks (sale_sequences/purchase_sequences/products/
-- product_variants) for the WHOLE transaction, but carried no timeout of
-- their own. A client whose request is left hanging holds those locks, and
-- every later write for that shop then queues on the same lock indefinitely
-- (lock wait, not deadlock — Postgres aborts deadlocks, so the wedged state
-- is a queue that never drains). QA observed create_sale_atomic and
-- adjust_stock_atomic hang for minutes with nothing ever returning.
--
-- This migration bounds that server-side: statement_timeout aborts a single
-- statement that runs too long, lock_timeout aborts a statement that waits on
-- a row lock too long, and idle_in_transaction_session_timeout reaps
-- connections that stop mid-transaction — all configured per-function so the
-- guard rides along when called through Supabase's RPC layer. The client
-- additionally bounds its own wait (lib/core/network/rpc_timeout.dart), but a
-- Dart timeout does NOT cancel the underlying HTTP socket; these function
-- settings are what actually release the row locks.
--
-- Values: statement 20s > lock 10s (a healthy call finishes in well under a
-- second; anything slower is wedged). No business validation is changed.
-- Append-only: never edit released migrations.
-- PostgreSQL allows only one SET clause per ALTER FUNCTION, so each setting
-- is applied as its own statement (values are unchanged).
-- ---------------------------------------------------------------------------

alter function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb)
  set statement_timeout = '20s';

alter function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb)
  set lock_timeout = '10s';

alter function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb)
  set idle_in_transaction_session_timeout = '30s';

alter function public.void_sale_atomic(uuid)
  set statement_timeout = '20s';

alter function public.void_sale_atomic(uuid)
  set lock_timeout = '10s';

alter function public.void_sale_atomic(uuid)
  set idle_in_transaction_session_timeout = '30s';

alter function public.receive_purchase_atomic(uuid, uuid, text, jsonb)
  set statement_timeout = '20s';

alter function public.receive_purchase_atomic(uuid, uuid, text, jsonb)
  set lock_timeout = '10s';

alter function public.receive_purchase_atomic(uuid, uuid, text, jsonb)
  set idle_in_transaction_session_timeout = '30s';

alter function public.adjust_stock_atomic(uuid, uuid, uuid, integer, text, text)
  set statement_timeout = '20s';

alter function public.adjust_stock_atomic(uuid, uuid, uuid, integer, text, text)
  set lock_timeout = '10s';

alter function public.adjust_stock_atomic(uuid, uuid, uuid, integer, text, text)
  set idle_in_transaction_session_timeout = '30s';

alter function public.next_receipt_number(uuid)
  set statement_timeout = '10s';

alter function public.next_receipt_number(uuid)
  set lock_timeout = '5s';

alter function public.next_purchase_number(uuid)
  set statement_timeout = '10s';

alter function public.next_purchase_number(uuid)
  set lock_timeout = '5s';