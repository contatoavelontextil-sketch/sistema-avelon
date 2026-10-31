begin;
drop policy quotes_view on public.quotes;
create policy quotes_view on public.quotes as restrictive for select to authenticated using(public.can('quotes','view') or public.can('workflow','view') or public.can('reports','view'));
create or replace function public.quote_print_data(p_quote uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ declare result jsonb;begin
 perform public.require_permission('quotes','print');
 select jsonb_build_object('quote',to_jsonb(q),'items',(select jsonb_agg(to_jsonb(i)) from public.quote_items i where i.quote_id=q.id and i.user_id=public.workspace_owner())) into result from public.quotes q where q.id=p_quote and q.user_id=public.workspace_owner();
 if result is null then raise exception 'Orçamento não encontrado';end if;return result;
end $$;
create function public.order_financials() returns table(quote_id uuid,paid numeric,pending numeric) language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not(public.can('workflow','view') or public.can('quotes','view')) then raise exception 'Sem permissão para consultar pedidos';end if;
 return query select q.id,coalesce(sum(s.amount) filter(where not s.reversed and not e.voided),0),q.total-coalesce(sum(s.amount) filter(where not s.reversed and not e.voided),0) from public.quotes q left join public.fin_entries e on e.quote_id=q.id left join public.fin_settlements s on s.entry_id=e.id where q.user_id=public.workspace_owner() group by q.id;
end $$;
revoke all on function public.order_financials() from public;
grant execute on function public.order_financials() to authenticated;
drop policy workspace_read on public.bank_accounts;
create policy workspace_read on public.bank_accounts for select to authenticated using(user_id=public.workspace_owner() and (public.can('finance','view') or public.can('bank','view') or public.can('settings_finance','view') or public.can('reports','view')));
create function public.authorize_report() returns boolean language plpgsql security definer set search_path=public,pg_temp as $$ begin perform public.require_permission('reports','print');return true;end $$;
revoke all on function public.authorize_report() from public;
grant execute on function public.authorize_report() to authenticated;
create function public.transfer_accounts(p_from uuid,p_to uuid,p_amount numeric,p_date date,p_note text,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid;b uuid;r uuid;second_request uuid:=md5(p_request::text||':incoming')::uuid;begin
 perform public.require_permission('finance','settle');perform public.require_permission('finance','create');
 select id into r from public.fin_settlements where request_id=p_request and user_id=public.workspace_owner();if r is not null then return r;end if;
 if p_from=p_to or p_amount<=0 or p_amount is null then raise exception 'Escolha contas diferentes e um valor positivo';end if;
 if(select count(*) from public.bank_accounts where id in(p_from,p_to) and user_id=public.workspace_owner() and active)<>2 then raise exception 'As duas contas devem estar ativas';end if;
 insert into public.fin_entries(kind,class,category,description,amount,due_date,competence) values('expense','transfer','Transferência entre contas',coalesce(nullif(p_note,''),'Transferência interna'),p_amount,p_date,p_date) returning id into a;
 insert into public.fin_entries(kind,class,category,description,amount,due_date,competence) values('income','transfer','Transferência entre contas',coalesce(nullif(p_note,''),'Transferência interna'),p_amount,p_date,p_date) returning id into b;
 r:=public.settle_entry(a,p_from,p_amount,p_date,'Transferência interna',p_request);perform public.settle_entry(b,p_to,p_amount,p_date,'Transferência interna',second_request);return r;
end $$;
revoke all on function public.transfer_accounts(uuid,uuid,numeric,date,text,uuid) from public;
grant execute on function public.transfer_accounts(uuid,uuid,numeric,date,text,uuid) to authenticated;
commit;
