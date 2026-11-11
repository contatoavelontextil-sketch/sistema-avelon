begin;
select set_config('request.jwt.claim.sub',public.workspace_owner()::text,true);
do $$declare owner_id uuid:=public.workspace_owner();begin
 perform public.admin_set_session_policy(owner_id,true,14400);
 if not exists(select 1 from public.profiles where id=owner_id and session_persistent and session_idle_minutes=14400) then raise exception 'Política do proprietário incorreta';end if;
 begin perform public.admin_set_session_policy(owner_id,true,14401);raise exception 'Prazo inválido aceito';exception when others then if SQLERRM='Prazo inválido aceito' then raise;end if;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
 begin perform public.admin_set_session_policy(owner_id,false,5);raise exception 'Alteração sem permissão aceita';exception when others then if SQLERRM='Alteração sem permissão aceita' then raise;end if;end;
end $$;
rollback;
begin;
set local role anon;
do $$declare t text;n bigint;begin
 foreach t in array array['clients','products','quotes','quote_items','settings','profiles','fin_entries','fin_settlements','bank_accounts','payment_receipts'] loop
  begin execute format('select count(*) from public.%I',t) into n;if n>0 then raise exception 'Acesso anônimo indevido em %',t;end if;exception when insufficient_privilege then null;end;
 end loop;
end $$;
select 'PASSOU: controle exclusivo do Mestre, limite de dez dias e leitura anônima bloqueada nas tabelas verificadas.' as resultado;
rollback;
