-- Create session_notes table if it doesn't exist
create table if not exists session_notes (
  id uuid default gen_random_uuid() primary key,
  session_id uuid references sessions(id) on delete cascade not null,
  content text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Index for faster lookups
create index if not exists session_notes_session_id_idx on session_notes(session_id);

-- Enable Row Level Security
alter table session_notes enable row level security;

-- Policies
create policy "Allow all access to session_notes"
  on session_notes for all
  using (true)
  with check (true);
