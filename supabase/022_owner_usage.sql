begin;
-- Somente números agregados; nenhum dado pessoal ou nome de arquivo é retornado.
create function public.owner_storage_usage() returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare db_bytes bigint; app_bytes bigint; file_bytes bigint; file_count bigint;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_owner) then
  raise exception 'Uso e armazenamento é exclusivo do Mestre Criador' using errcode='42501';
 end if;
 select pg_database_size(current_database()) into db_bytes;
 select coalesce(sum(pg_total_relation_size(c.oid)),0) into app_bytes
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in ('r','m');
 select coalesce(sum(case when (metadata->>'size') ~ '^[0-9]+$' then (metadata->>'size')::numeric else 0 end),0)::bigint,count(*)
 into file_bytes,file_count from storage.objects;
 return jsonb_build_object('measured_at',clock_timestamp(),'database_bytes',db_bytes,'app_tables_bytes',app_bytes,'storage_bytes',file_bytes,'storage_objects',file_count);
end $$;
revoke all on function public.owner_storage_usage() from public,anon;
grant execute on function public.owner_storage_usage() to authenticated;
commit;
