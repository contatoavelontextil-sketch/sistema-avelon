begin;
select set_config('request.jwt.claim.sub',public.workspace_owner()::text,true);
do $$
declare q uuid; r jsonb; before_events bigint; s text;
begin
 -- Clone a snapshot only within this rolled-back test; no financial entries.
 insert into public.quotes(user_id,client_id,client_snapshot,method,percentage,notes,valid_until,total,stage)
 select user_id,client_id,client_snapshot,method,percentage,'TESTE TRANSACIONAL EXPORTAÇÃO',valid_until,total,'draft' from public.quotes limit 1 returning id into q;
 if q is null then raise exception 'Sem base para teste';end if;
 r:=public.mark_quote_sent(q,'download');
 if r->>'stage'<>'sent' or (r->>'changed')::boolean is not true then raise exception 'Rascunho não enviado';end if;
 select count(*) into before_events from public.quote_events where quote_id=q;
 r:=public.mark_quote_sent(q,'share');
 if (r->>'changed')::boolean or (select count(*) from public.quote_events where quote_id=q)<>before_events then raise exception 'Exportação duplicou evento';end if;
 foreach s in array array['production','completed','cancelled','suspended','awaiting_deposit'] loop
 update public.quotes set stage=s where id=q;
 r:=public.mark_quote_sent(q,'download');
 if r->>'stage'<>s or (r->>'changed')::boolean then raise exception 'Etapa regrediu: %',s;end if;
 end loop;
 begin
 perform public.mark_quote_sent(q,'invalid');raise exception 'Canal inválido aceito';
 exception when others then if SQLERRM='Canal inválido aceito' then raise;end if;end;
end $$;
select 'Exportação: transição, repetição e preservação de etapas OK; dados de teste revertidos' as resultado;
rollback;
