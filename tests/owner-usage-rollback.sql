begin;

select set_config('request.jwt.claim.sub',public.workspace_owner()::text,true);
do $$ declare r jsonb; denied boolean:=false;begin
 r:=public.owner_storage_usage();
 if (r->>'database_bytes')::bigint<=0 or (r->>'storage_bytes')::bigint<0 then raise exception 'Medição inválida';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
 begin perform public.owner_storage_usage();exception when insufficient_privilege then denied:=true;end;
 if not denied then raise exception 'Usuário sem perfil acessou medição';end if;
 if has_function_privilege('anon','public.owner_storage_usage()','execute') then raise exception 'Anônimo executa medição';end if;
end $$;
select 'PASSOU: medição real, acesso sem perfil e anônimo bloqueados.' as resultado;
rollback;
