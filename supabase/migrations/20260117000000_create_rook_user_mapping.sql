-- Create mapping table for Rook user IDs to Miya auth UUIDs
-- This allows the webhook to map Rook's internal user identifiers to our auth.users

create table if not exists rook_user_mapping (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  
  -- Miya auth user UUID (links to auth.users)
  user_id uuid not null references auth.users(id) on delete cascade,
  
  -- Rook's user identifier (can be their internal ID or the client_user_id we set)
  rook_user_id text not null,
  
  -- Source for debugging (e.g., 'sdk', 'api', 'manual')
  mapping_source text default 'sdk',
  
  -- Last time this mapping was verified/updated
  last_verified_at timestamptz default now()
);

-- Unique constraint: one Rook user ID maps to one Miya user
create unique index if not exists idx_rook_user_mapping_rook_id 
  on rook_user_mapping (rook_user_id);

-- Index for reverse lookup (find all Rook IDs for a Miya user)
create index if not exists idx_rook_user_mapping_user_id 
  on rook_user_mapping (user_id);

-- Trigger to update updated_at
create trigger update_rook_user_mapping_updated_at
  before update on rook_user_mapping
  for each row
  execute function update_updated_at_column();

-- Comment for documentation
comment on table rook_user_mapping is 'Maps Rook user identifiers to Miya auth UUIDs for webhook processing';
