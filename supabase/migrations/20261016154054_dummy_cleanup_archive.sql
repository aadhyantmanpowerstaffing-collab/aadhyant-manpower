begin;
create table private.dummy_cleanup_archive_20261016(relation_name text primary key,row_count integer not null,snapshot jsonb not null,archived_at timestamptz not null default clock_timestamp(),check(jsonb_typeof(snapshot)='array' and jsonb_array_length(snapshot)=row_count));
alter table private.dummy_cleanup_archive_20261016 enable row level security;
revoke all on private.dummy_cleanup_archive_20261016 from public,anon,authenticated,service_role;
comment on table private.dummy_cleanup_archive_20261016 is 'User-authorized dummy-data cleanup, 16 Oct 2026. Restricted logical recovery copy; no browser access.';
commit;
