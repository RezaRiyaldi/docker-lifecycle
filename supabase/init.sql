create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema if not exists auth;
create schema if not exists storage;
create schema if not exists graphql_public;
create schema if not exists _realtime;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema storage to anon, authenticated, service_role;
grant usage on schema graphql_public to anon, authenticated, service_role;

grant all on schema public to service_role;
grant all on schema auth to service_role;
grant all on schema storage to service_role;
grant all on schema graphql_public to service_role;
grant all on schema _realtime to service_role;
