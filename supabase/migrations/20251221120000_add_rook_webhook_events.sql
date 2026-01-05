-- Create table to store incoming Rook webhook events
create table if not exists rook_webhook_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  headers jsonb not null,
  payload jsonb not null,
  raw_body text null,
  source text default 'rook'
);


