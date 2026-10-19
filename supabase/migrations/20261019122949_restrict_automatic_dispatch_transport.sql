-- Only protect outgoing credential headers from browser reads; retain provider/service privileges.
begin;
revoke select on table net.http_request_queue from public,anon,authenticated;
commit;
