begin;
create table public.payment_receipts(
 id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),number bigint generated always as identity unique,
 quote_id uuid not null,amount numeric(14,2) not null check(amount>0),settlement_ids uuid[] not null check(cardinality(settlement_ids)>0),snapshot jsonb not null,
 request_id uuid not null unique,created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),
 foreign key(quote_id,user_id) references public.quotes(id,user_id),check(octet_length(snapshot::text)<2500000));
alter table public.payment_receipts enable row level security;
create policy receipts_read on public.payment_receipts for select to authenticated using(user_id=public.workspace_owner() and public.can('receipts','view'));
revoke all on public.payment_receipts from public,anon,authenticated;
grant select on public.payment_receipts to authenticated;
create index on public.payment_receipts(user_id,quote_id);
create function public.receipt_is_reversed(p_receipt uuid) returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce((select exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided)) from public.payment_receipts r where r.id=p_receipt and r.user_id=public.workspace_owner() and public.can('receipts','view')),true)
$$;
revoke all on function public.receipt_is_reversed(uuid) from public;
grant execute on function public.receipt_is_reversed(uuid) to authenticated;
create function public.list_payment_receipts(p_quote uuid default null) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ begin
 perform public.require_permission('receipts','view');
 return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'quote_id',r.quote_id,'amount',r.amount,'created_at',r.created_at,'reversed',public.receipt_is_reversed(r.id)) order by r.created_at desc) from public.payment_receipts r where r.user_id=public.workspace_owner() and (p_quote is null or r.quote_id=p_quote)),'[]'::jsonb);
end $$;
create function public.issue_payment_receipt(p_quote uuid,p_amount numeric,p_message text,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;config jsonb;company jsonb;paid numeric;issued numeric;ids uuid[];r uuid;message text;stage_label text;begin
 perform public.require_permission('receipts','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found or q.stage in('cancelled','suspended') then raise exception 'Pedido indisponível para emissão de recibo';end if;
 select id into r from public.payment_receipts where request_id=p_request and user_id=q.user_id;if r is not null then return r;end if;
 if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) then raise exception 'Informe um valor positivo com até duas casas decimais';end if;
 select coalesce(sum(s.amount),0),array_agg(s.id order by s.paid_on,s.created_at) into paid,ids from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 select coalesce(sum(r.amount),0) into issued from public.payment_receipts r where r.quote_id=q.id and not exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided));
 if p_amount>paid-issued then raise exception 'O recibo supera o recebimento disponível. Recebido: %, já documentado: %',paid,issued;end if;
 select data into config from public.settings where user_id=q.user_id;config:=coalesce(config,'{}'::jsonb);
 company:=jsonb_build_object('company',config->>'company','contact',config->>'contact','logo',config->>'logo','signature',config->>'signature','signature_name',config->>'signature_name','signature_invert',config->'signature_invert','city',config->>'city');
 message:=coalesce(nullif(trim(p_message),''),nullif(config->'budget'->>'receipt_message',''),'Agradecemos o adiantamento e a confiança na Avelon Têxtil. Seu pedido seguirá para o corte da malha, a personalização prevista no orçamento e a costura. Cada etapa será realizada com atenção aos detalhes, cuidado nos acabamentos e compromisso com a qualidade. Manteremos você informado até a conclusão.');
 if length(message)>5000 then raise exception 'O texto do recibo pode ter até 5.000 caracteres';end if;
 select x->>'label' into stage_label from jsonb_array_elements(coalesce(config->'production'->'stages',public.default_stages())) x where x->>'key'=q.stage;
 insert into public.payment_receipts(quote_id,amount,settlement_ids,request_id,snapshot) values(q.id,p_amount,ids,p_request,jsonb_build_object('company',company,'client',q.client_snapshot,'quote_number',q.number,'quote_total',q.total,'agreed_entry_amount',q.production->'agreed_entry_amount','received_total',paid,'remaining',greatest(0,q.total-paid),'stage',coalesce(stage_label,q.stage),'technique',q.production->>'technique','delivery_date',q.delivery_date,'message',message,'title',coalesce(config->'budget'->>'receipt_title','Recibo de adiantamento'),'show_logo',coalesce((config->'budget'->>'receipt_show_logo')::boolean,true),'show_signature',coalesce((config->'budget'->>'receipt_show_signature')::boolean,true),'items',coalesce((select jsonb_agg(jsonb_build_object('description',i.description,'quantity',i.quantity,'details',i.details) order by i.id) from public.quote_items i where i.quote_id=q.id),'[]'::jsonb))) returning id into r;
 insert into public.fin_audit(object_id,action,detail) values(r,'receipt_issued',jsonb_build_object('quote_id',q.id,'amount',p_amount));return r;
end $$;
create function public.receipt_print_data(p_receipt uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ declare r public.payment_receipts;current_stage text;begin
 perform public.require_permission('receipts','print');select * into r from public.payment_receipts where id=p_receipt and user_id=public.workspace_owner();if not found then raise exception 'Recibo indisponível';end if;
 select stage into current_stage from public.quotes where id=r.quote_id;
 return jsonb_build_object('receipt',to_jsonb(r),'reversed',exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided)),'current_stage',current_stage);
end $$;
create function public.receipt_view_data(p_receipt uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ declare r public.payment_receipts;current_stage text;begin
 perform public.require_permission('receipts','view');select * into r from public.payment_receipts where id=p_receipt and user_id=public.workspace_owner();if not found then raise exception 'Recibo indisponível';end if;
 select stage into current_stage from public.quotes where id=r.quote_id;
 return jsonb_build_object('receipt',to_jsonb(r),'reversed',exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided)),'current_stage',current_stage);
end $$;
create function public.start_order_with_receipt(p_quote uuid,p_stage text,p_delivery date,p_production jsonb,p_note text,p_expected timestamptz,p_amount numeric,p_record_payment boolean,p_adjust_deposit boolean,p_account uuid,p_paid_on date,p_method text,p_message text,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;e public.fin_entries;paid numeric;issued numeric;left_to_pay numeric;part numeric;balance numeric;r uuid;begin
 perform public.require_permission('workflow','edit');perform public.require_permission('receipts','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 select id into r from public.payment_receipts where request_id=p_request and user_id=q.user_id;if r is not null then return r;end if;
 if p_expected is not null and q.updated_at<>p_expected then raise exception 'O pedido foi alterado. Atualize antes de continuar';end if;
 if q.stage in('cancelled','suspended','completed') then raise exception 'Retome o pedido antes de iniciar a produção';end if;
 if p_stage not in('production','cutting','personalization','sewing','ready') and not exists(select 1 from public.settings t,jsonb_array_elements(coalesce(t.data->'production'->'stages','[]'::jsonb)) x where t.user_id=q.user_id and x->>'key'=p_stage and coalesce((x->>'requires_production')::boolean,false)) then raise exception 'Escolha uma etapa de produção';end if;
 if p_amount is null or p_amount<=0 or p_amount>q.total then raise exception 'Informe o valor do adiantamento, até o total do pedido';end if;
 select coalesce(sum(s.amount),0) into paid from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 select coalesce(sum(r.amount),0) into issued from public.payment_receipts r where r.quote_id=q.id and not exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided));
 if p_adjust_deposit then
  perform public.require_permission('finance','edit');if issued>0 then raise exception 'A entrada deve ser ajustada antes do primeiro recibo válido';end if;
  if exists(select 1 from public.fin_entries e where e.quote_id=q.id and e.voided and ((e.installment=1 and p_amount>0) or (e.installment=2 and q.total-p_amount>0))) then raise exception 'Reative as parcelas canceladas antes de ajustar a entrada';end if;
  if exists(select 1 from public.fin_entries e where e.quote_id=q.id and e.installment in(1,2) and (select coalesce(sum(s.amount),0) from public.fin_settlements s where s.entry_id=e.id and not s.reversed)>case when e.installment=1 then p_amount else q.total-p_amount end) then raise exception 'O ajuste não pode reduzir uma parcela abaixo do valor já baixado. Emita o recibo sem alterar a entrada acordada';end if;
  p_production:=coalesce(p_production,'{}'::jsonb)||jsonb_build_object('agreed_entry_amount',p_amount);
  update public.quotes set production=p_production where id=q.id;
  perform public.prepare_receivables(q.id,coalesce(p_paid_on,current_date),coalesce(p_delivery,p_paid_on,current_date));
  update public.fin_entries set amount=p_amount where quote_id=q.id and installment=1 and not voided;
  if q.total-p_amount>0 then update public.fin_entries set amount=q.total-p_amount where quote_id=q.id and installment=2 and not voided;
  elsif exists(select 1 from public.fin_entries where quote_id=q.id and installment=2 and not voided) then perform public.require_permission('finance','delete');update public.fin_entries set voided=true,void_reason='Saldo incorporado à entrada integral acordada' where quote_id=q.id and installment=2 and not voided;end if;
  insert into public.fin_audit(object_id,action,detail) values(q.id,'deposit_adjusted',jsonb_build_object('amount',p_amount,'remaining',q.total-p_amount));
 end if;
 if p_record_payment and issued+p_amount>paid then
  perform public.require_permission('finance','create');perform public.require_permission('finance','settle');
  perform public.prepare_receivables(q.id,p_paid_on,coalesce(p_delivery,p_paid_on));left_to_pay:=round(issued+p_amount-paid,2);
  for e in select * from public.fin_entries where quote_id=q.id and not voided order by installment,created_at for update loop
   select e.amount-coalesce(sum(s.amount),0) into balance from public.fin_settlements s where s.entry_id=e.id and not s.reversed;
   part:=least(left_to_pay,balance);if part>0 then perform public.settle_entry(e.id,p_account,part,p_paid_on,coalesce(p_method,'')||' · Adiantamento para produção',md5(p_request::text||':'||e.id::text)::uuid);left_to_pay:=left_to_pay-part;end if;exit when left_to_pay<=0;
  end loop;
  if left_to_pay>0 then raise exception 'Revise ou reative as parcelas deste pedido antes de receber';end if;
 end if;
 perform public.update_order(q.id,p_stage,p_delivery,p_production,p_note,p_expected);
 return public.issue_payment_receipt(q.id,p_amount,p_message,p_request);
end $$;
revoke all on function public.receipt_view_data(uuid),public.list_payment_receipts(uuid),public.issue_payment_receipt(uuid,numeric,text,uuid),public.receipt_print_data(uuid),public.start_order_with_receipt(uuid,text,date,jsonb,text,timestamptz,numeric,boolean,boolean,uuid,date,text,text,uuid) from public;
grant execute on function public.receipt_view_data(uuid),public.list_payment_receipts(uuid),public.issue_payment_receipt(uuid,numeric,text,uuid),public.receipt_print_data(uuid),public.start_order_with_receipt(uuid,text,date,jsonb,text,timestamptz,numeric,boolean,boolean,uuid,date,text,text,uuid) to authenticated;
commit;
