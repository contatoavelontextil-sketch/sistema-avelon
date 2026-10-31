begin;
alter table public.fin_entries add column transfer_group uuid;
create or replace function public.transfer_accounts(p_from uuid,p_to uuid,p_amount numeric,p_date date,p_note text,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare a uuid;b uuid;r uuid;second_request uuid:=md5(p_request::text||':incoming')::uuid;begin
 perform public.require_permission('finance','settle');perform public.require_permission('finance','create');
 select id into r from public.fin_settlements where request_id=p_request and user_id=public.workspace_owner();if r is not null then return r;end if;
 if p_from=p_to or p_amount<=0 or p_amount is null then raise exception 'Escolha contas diferentes e um valor positivo';end if;
 if(select count(*) from public.bank_accounts where id in(p_from,p_to) and user_id=public.workspace_owner() and active)<>2 then raise exception 'As duas contas devem estar ativas';end if;
 insert into public.fin_entries(kind,class,category,description,amount,due_date,competence) values('expense','transfer','Transferência entre contas',coalesce(nullif(p_note,''),'Transferência interna'),p_amount,p_date,p_date) returning id into a;
 insert into public.fin_entries(kind,class,category,description,amount,due_date,competence) values('income','transfer','Transferência entre contas',coalesce(nullif(p_note,''),'Transferência interna'),p_amount,p_date,p_date) returning id into b;
 update public.fin_entries set transfer_group=p_request where id in(a,b);
 r:=public.settle_entry(a,p_from,p_amount,p_date,'Transferência interna',p_request);perform public.settle_entry(b,p_to,p_amount,p_date,'Transferência interna',second_request);return r;
end $$;
create or replace function public.reverse_settlement(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public,pg_temp as $$ declare s public.fin_settlements;g uuid;begin
 perform public.require_permission('finance','reverse');if length(trim(p_reason))<3 then raise exception 'Informe o motivo do estorno';end if;
 select * into s from public.fin_settlements where id=p_id and user_id=public.workspace_owner() for update;if not found or s.reversed then raise exception 'Baixa indisponível';end if;
 select transfer_group into g from public.fin_entries where id=s.entry_id;
 if g is not null then
  update public.bank_lines set status='pending' where id in(select statement_id from public.fin_settlements where entry_id in(select id from public.fin_entries where transfer_group=g) and not reversed);
  update public.fin_settlements set reversed=true,reversal_reason=p_reason,statement_id=null where entry_id in(select id from public.fin_entries where transfer_group=g) and not reversed;
  update public.fin_entries set voided=true,void_reason=p_reason where transfer_group=g;
  insert into public.fin_audit(object_id,action,detail) values(g,'transfer_reversed',jsonb_build_object('reason',p_reason));return;
 end if;
 if s.statement_id is not null then update public.bank_lines set status='pending' where id=s.statement_id;end if;
 update public.fin_settlements set reversed=true,reversal_reason=p_reason,statement_id=null where id=s.id;
 insert into public.fin_audit(object_id,action,detail) values(s.id,'reversed',jsonb_build_object('reason',p_reason));end $$;
create or replace function public.update_order(p_quote uuid,p_stage text,p_delivery date,p_production jsonb,p_note text,p_expected timestamptz) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;c jsonb;s jsonb;paid numeric;begin
 perform public.require_permission('workflow','edit');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 if p_expected is not null and q.updated_at<>p_expected then raise exception 'O pedido foi alterado. Atualize o quadro antes de salvar';end if;
 select data into c from public.settings where user_id=q.user_id;c:=coalesce(c,'{}'::jsonb);s:=coalesce(c->'production'->'stages',public.default_stages());
 if not exists(select 1 from jsonb_array_elements(s) x where x->>'key'=p_stage and coalesce((x->>'enabled')::boolean,true)) then raise exception 'Etapa não disponível';end if;
 select coalesce(sum(s.amount),0) into paid from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 if coalesce((c->'production'->>'require_deposit')::boolean,true) and (p_stage in ('production','cutting','personalization','ready') or exists(select 1 from jsonb_array_elements(s) x where x->>'key'=p_stage and coalesce((x->>'requires_production')::boolean,false))) and paid<round(q.total*q.entry_percentage/100,2) then raise exception 'Registre a entrada acordada antes de iniciar a produção';end if;
 if coalesce((c->'production'->>'require_art')::boolean,true) and (p_stage in ('production','cutting','personalization','ready') or exists(select 1 from jsonb_array_elements(s) x where x->>'key'=p_stage and coalesce((x->>'requires_production')::boolean,false))) and not coalesce((p_production->>'art_approved')::boolean,false) then raise exception 'Confirme a aprovação da arte antes da produção';end if;
 if coalesce((c->'production'->>'require_balance')::boolean,true) and p_stage='completed' and paid<q.total then raise exception 'Ainda existe saldo a receber neste pedido';end if;
 if p_stage in ('cancelled','suspended') and length(trim(coalesce(p_note,'')))<3 then raise exception 'Informe o motivo do cancelamento ou suspensão';end if;
 update public.quotes set stage=p_stage,delivery_date=p_delivery,production=coalesce(p_production,'{}'::jsonb),updated_at=now() where id=q.id;
 insert into public.quote_events(user_id,quote_id,actor_id,previous_stage,next_stage,note) values(q.user_id,q.id,auth.uid(),q.stage,p_stage,coalesce(p_note,''));
end $$;

commit;