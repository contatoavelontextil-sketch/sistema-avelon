begin;

-- One atomic request covers the stage, any actual receipt of money and its document.
-- The journal is private to the RPC. Clients cannot insert/replay journal rows directly.
create table public.order_payment_requests (
 user_id uuid not null references auth.users(id),
 request_id uuid not null,
 quote_id uuid not null references public.quotes(id),
 actor_id uuid not null references auth.users(id),
 fingerprint text not null,
 result jsonb not null,
 created_at timestamptz not null default now(),
 primary key(user_id,request_id)
);
alter table public.order_payment_requests enable row level security;
revoke all on table public.order_payment_requests from public,anon,authenticated;

create function public.advance_order_with_payment(
 p_quote uuid,p_stage text,p_delivery date,p_production jsonb,p_note text,p_expected timestamptz,
 p_received boolean,p_amount numeric,p_account uuid,p_paid_on date,p_method text,p_message text,p_request uuid
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 q public.quotes;entry_row public.fin_entries;prior public.order_payment_requests;
 paid numeric;issued numeric;balance numeric;left_to_pay numeric;part numeric;available numeric;
 receipt_id uuid;answer jsonb;fingerprint text;note text;
begin
 perform public.require_permission('workflow','edit');
 perform public.require_permission('receipts','view');
 perform public.require_permission('receipts','create');
 if p_request is null or p_received is null then raise exception 'Confirme se o cliente já pagou';end if;
 fingerprint:=md5(jsonb_build_array(p_quote,p_stage,p_delivery,p_production,p_note,p_expected,p_received,p_amount,p_account,p_paid_on,p_method,p_message)::text);
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;
 if not found then raise exception 'Pedido não encontrado';end if;
 select * into prior from public.order_payment_requests where user_id=q.user_id and request_id=p_request;
 if found then
  if prior.quote_id<>q.id or prior.actor_id<>auth.uid() or prior.fingerprint<>fingerprint then raise exception 'Essa confirmação já foi utilizada. Atualize o pedido';end if;
  return prior.result;
 end if;
 if q.superseded_by is not null then raise exception 'Abra a revisão atual deste pedido';end if;
 if q.stage in ('cancelled','suspended') then raise exception 'Retome o pedido antes de confirmar o recebimento';end if;
 if p_expected is null or q.updated_at<>p_expected then raise exception 'O pedido foi alterado. Atualize o quadro antes de confirmar';end if;
 if p_stage in ('cancelled','suspended') or p_stage is null then raise exception 'Use o motivo próprio para cancelar ou suspender';end if;
 if q.total<=0 then raise exception 'O recibo exige um pedido com valor positivo';end if;
 if length(coalesce(p_message,''))>5000 then raise exception 'O texto do recibo pode ter até 5.000 caracteres';end if;
 perform 1 from public.fin_entries where quote_id=q.id order by installment,id for update;
 select coalesce(sum(s.amount),0) into paid from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not e.voided and not s.reversed;
 if p_received then
  perform public.require_permission('finance','create');perform public.require_permission('finance','settle');
  if q.stage='completed' then raise exception 'Pedido já finalizado. Abra seu recibo existente';end if;
  if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) or p_amount>q.total-paid then raise exception 'O valor recebido supera o saldo ou é inválido. Atualize o pedido';end if;
  if p_paid_on is null or p_paid_on>(clock_timestamp() at time zone 'America/Sao_Paulo')::date then raise exception 'Informe a data em que o pagamento já foi recebido';end if;
  if length(trim(coalesce(p_method,''))) not between 1 and 100 then raise exception 'Informe a forma de pagamento';end if;
  if not exists(select 1 from public.bank_accounts where id=p_account and user_id=q.user_id and active) then raise exception 'Selecione uma conta ativa que recebeu o pagamento';end if;
  perform public.prepare_receivables(q.id,p_paid_on,greatest(coalesce(p_delivery,p_paid_on),p_paid_on));
  left_to_pay:=p_amount;
  for entry_row in select * from public.fin_entries where quote_id=q.id and kind='income' and not voided order by installment,created_at,id for update loop
   select entry_row.amount-coalesce(sum(s.amount),0) into balance from public.fin_settlements s where s.entry_id=entry_row.id and not s.reversed;
   part:=least(left_to_pay,balance);
   if part>0 then
    perform public.settle_entry(entry_row.id,p_account,part,p_paid_on,p_method||' · Recebimento confirmado ao atualizar o pedido',md5(p_request::text||':'||entry_row.id::text)::uuid);
    left_to_pay:=left_to_pay-part;
   end if;
   exit when left_to_pay<=0;
  end loop;
  if left_to_pay>0 then raise exception 'As parcelas não cobrem o recebimento. Revise os títulos cancelados no Financeiro';end if;
 elsif coalesce(p_amount,0)<>0 then
  raise exception 'Sem confirmação de recebimento, o valor da nova baixa deve ser zero';
 end if;

 note:=case when p_stage='completed' and q.stage in ('production','cutting','personalization','sewing') then 'Finalização direta, sem passagem registrada pelas etapas intermediárias.' else coalesce(p_note,'') end;
 if p_stage='completed' then
  -- This existing RPC validates full payment and creates the consolidated history.
  receipt_id:=public.complete_order_with_receipt(q.id,p_stage,p_delivery,p_production,note,p_expected,p_request);
 else
  -- No fabricated stage events when issuing a receipt from the current stage.
  if (q.stage,q.delivery_date,q.production) is distinct from (p_stage,p_delivery,p_production) then
   perform public.update_order(q.id,p_stage,p_delivery,p_production,note,p_expected);
  end if;
  select coalesce(sum(s.amount),0) into paid from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not e.voided and not s.reversed;
  select coalesce(sum(r.amount),0) into issued from public.payment_receipts r where r.quote_id=q.id and r.kind='payment' and not public.receipt_is_reversed(r.id);
  available:=round(greatest(0,paid-issued),2);
  if available>0 then receipt_id:=public.issue_payment_receipt(q.id,available,p_message,p_request);
  else select r.id into receipt_id from public.payment_receipts r where r.quote_id=q.id and r.kind='payment' and not public.receipt_is_reversed(r.id) order by r.created_at desc limit 1;end if;
 end if;
 answer:=jsonb_build_object('receipt',receipt_id,'ready',p_stage='ready' and q.stage<>'ready','recorded',case when p_received then p_amount else 0 end);
 insert into public.order_payment_requests(user_id,request_id,quote_id,actor_id,fingerprint,result) values(q.user_id,p_request,q.id,auth.uid(),fingerprint,answer);
 insert into public.fin_audit(object_id,action,detail) values(q.id,'order_payment_confirmed',jsonb_build_object('request',p_request,'stage',p_stage,'received',p_received,'amount',case when p_received then p_amount else 0 end,'receipt',receipt_id));
 return answer;
end $$;
revoke all on function public.advance_order_with_payment(uuid,text,date,jsonb,text,timestamptz,boolean,numeric,uuid,date,text,text,uuid) from public;
grant execute on function public.advance_order_with_payment(uuid,text,date,jsonb,text,timestamptz,boolean,numeric,uuid,date,text,text,uuid) to authenticated;

-- Cached versions must not turn a second deposit receipt into payment of the delivery balance.
create or replace function public.start_order_with_receipt(p_quote uuid,p_stage text,p_delivery date,p_production jsonb,p_note text,p_expected timestamptz,p_amount numeric,p_record_payment boolean,p_adjust_deposit boolean,p_account uuid,p_paid_on date,p_method text,p_message text,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;entry_row public.fin_entries;paid numeric;issued numeric;left_to_pay numeric;part numeric;balance numeric;r uuid;begin
 perform public.require_permission('workflow','edit');perform public.require_permission('receipts','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 select id into r from public.payment_receipts where request_id=p_request and user_id=q.user_id;if r is not null then return r;end if;
 if p_expected is not null and q.updated_at<>p_expected then raise exception 'O pedido foi alterado. Atualize antes de continuar';end if;
 if q.stage in('cancelled','suspended','completed') then raise exception 'Retome o pedido antes de iniciar a produção';end if;
 if p_stage not in('production','cutting','personalization','sewing','ready') and not exists(select 1 from public.settings t,jsonb_array_elements(coalesce(t.data->'production'->'stages','[]'::jsonb)) x where t.user_id=q.user_id and x->>'key'=p_stage and coalesce((x->>'requires_production')::boolean,false)) then raise exception 'Escolha uma etapa de produção';end if;
 if p_amount is null or p_amount<=0 or p_amount>q.total then raise exception 'Informe o valor do adiantamento, até o total do pedido';end if;
 perform 1 from public.fin_entries where quote_id=q.id order by installment,id for update;
 select coalesce(sum(s.amount),0) into paid from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 select coalesce(sum(r.amount),0) into issued from public.payment_receipts r where r.quote_id=q.id and r.kind='payment' and not exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided));
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
 if p_record_payment and issued+p_amount>paid and issued+p_amount>(case when p_adjust_deposit then p_amount else coalesce((q.production->>'agreed_entry_amount')::numeric,round(q.total*q.entry_percentage/100,2)) end) then
  raise exception 'A entrada já foi recebida ou o valor inclui o saldo da entrega. Atualize o sistema e confirme um novo recebimento pela janela de pagamento';
 end if;
 if p_record_payment and issued+p_amount>paid then
  perform public.require_permission('finance','create');perform public.require_permission('finance','settle');
  perform public.prepare_receivables(q.id,p_paid_on,coalesce(p_delivery,p_paid_on));left_to_pay:=round(issued+p_amount-paid,2);
  for entry_row in select * from public.fin_entries where quote_id=q.id and not voided order by installment,created_at for update loop
   select entry_row.amount-coalesce(sum(s.amount),0) into balance from public.fin_settlements s where s.entry_id=entry_row.id and not s.reversed;
   part:=least(left_to_pay,balance);if part>0 then perform public.settle_entry(entry_row.id,p_account,part,p_paid_on,coalesce(p_method,'')||' · Adiantamento para produção',md5(p_request::text||':'||entry_row.id::text)::uuid);left_to_pay:=left_to_pay-part;end if;exit when left_to_pay<=0;
  end loop;
  if left_to_pay>0 then raise exception 'Revise ou reative as parcelas deste pedido antes de receber';end if;
 end if;
 perform public.update_order(q.id,p_stage,p_delivery,p_production,p_note,p_expected);
 return public.issue_payment_receipt(q.id,p_amount,p_message,p_request);
end $$;
commit;
