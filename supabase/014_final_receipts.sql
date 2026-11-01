begin;
alter table public.payment_receipts add column kind text not null default 'payment' check(kind in('payment','final'));
create function public.issue_final_receipt(p_quote uuid,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;cfg jsonb;paid numeric;ids uuid[];payments jsonb;advances jsonb;result_id uuid;begin
 perform public.require_permission('receipts','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;
 if not found or q.stage<>'completed' then raise exception 'Finalize o pedido para emitir o recibo de quitação';end if;
 select coalesce(sum(s.amount),0),array_agg(s.id order by s.paid_on,s.created_at) into paid,ids from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 if paid<q.total or paid<=0 then raise exception 'O recibo final exige quitação integral registrada no financeiro';end if;
 select r.id into result_id from public.payment_receipts r where r.quote_id=q.id and r.kind='final' and not exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided)) order by r.created_at desc limit 1;
 if result_id is not null then return result_id;end if;
 select coalesce(data,'{}'::jsonb) into cfg from public.settings where user_id=q.user_id;
 select jsonb_agg(jsonb_build_object('date',s.paid_on,'amount',s.amount,'description',e.description,'installment',e.installment,'method',case when split_part(s.memo,' · ',1) in ('Pix','Dinheiro','Crédito','Débito','Transferência','Boleto') then split_part(s.memo,' · ',1) else 'Registrado no financeiro' end) order by s.paid_on,s.created_at) into payments from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 select coalesce(jsonb_agg(jsonb_build_object('number',r.number,'date',r.created_at,'amount',r.amount) order by r.created_at),'[]'::jsonb) into advances from public.payment_receipts r where r.quote_id=q.id and r.kind='payment' and not exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided));
 insert into public.payment_receipts(quote_id,amount,settlement_ids,request_id,kind,snapshot) values(q.id,paid,ids,p_request,'final',jsonb_build_object(
 'company',jsonb_build_object('company',cfg->>'company','contact',cfg->>'contact','logo',cfg->>'logo','signature',cfg->>'signature','signature_name',cfg->>'signature_name','signature_invert',cfg->'signature_invert','city',cfg->>'city'),
 'client',q.client_snapshot,'quote_number',q.number,'quote_total',q.total,'received_total',paid,'remaining',0,'stage','Finalizado','technique',q.production->>'technique','delivery_date',q.delivery_date,'completed_on',coalesce((select max(created_at) from public.quote_events where quote_id=q.id and next_stage='completed'),q.updated_at),'last_payment_amount',(select s.amount from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided order by s.paid_on desc,s.created_at desc limit 1),'payments',payments,'advance_receipts',advances,
 'message',coalesce(nullif(cfg->'budget'->>'final_receipt_message',''),'Agradecemos a confiança na Avelon Têxtil. Seu pedido foi concluído e os pagamentos foram integralmente confirmados. Foi um prazer cuidar de cada etapa da produção. Esperamos fazer parte dos seus próximos projetos.'),
 'title',coalesce(nullif(cfg->'budget'->>'final_receipt_title',''),'Recibo final de quitação'),'show_logo',coalesce((cfg->'budget'->>'receipt_show_logo')::boolean,true),'show_signature',coalesce((cfg->'budget'->>'receipt_show_signature')::boolean,true),
 'items',coalesce((select jsonb_agg(jsonb_build_object('description',i.description,'quantity',i.quantity,'details',i.details) order by i.id) from public.quote_items i where i.quote_id=q.id),'[]'::jsonb))) returning id into result_id;
 insert into public.fin_audit(object_id,action,detail) values(result_id,'final_receipt_issued',jsonb_build_object('quote_id',q.id,'total',paid));return result_id;
end $$;
create function public.complete_order_with_receipt(p_quote uuid,p_stage text,p_delivery date,p_production jsonb,p_note text,p_expected timestamptz,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$ declare existing uuid;begin
 perform public.require_permission('workflow','edit');perform public.require_permission('receipts','create');
 select id into existing from public.payment_receipts where request_id=p_request and quote_id=p_quote and user_id=public.workspace_owner() and kind='final';if existing is not null then return existing;end if;
 if p_stage<>'completed' then raise exception 'Escolha Finalizado para emitir a quitação';end if;
 perform public.update_order(p_quote,p_stage,p_delivery,p_production,p_note,p_expected);
 return public.issue_final_receipt(p_quote,p_request);
end $$;
revoke all on function public.issue_final_receipt(uuid,uuid),public.complete_order_with_receipt(uuid,text,date,jsonb,text,timestamptz,uuid) from public;
grant execute on function public.issue_final_receipt(uuid,uuid),public.complete_order_with_receipt(uuid,text,date,jsonb,text,timestamptz,uuid) to authenticated;
create or replace function public.issue_payment_receipt(p_quote uuid,p_amount numeric,p_message text,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;config jsonb;company jsonb;paid numeric;issued numeric;ids uuid[];r uuid;message text;stage_label text;begin
 perform public.require_permission('receipts','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found or q.stage in('cancelled','suspended') then raise exception 'Pedido indisponível para emissão de recibo';end if;
 select id into r from public.payment_receipts where request_id=p_request and user_id=q.user_id;if r is not null then return r;end if;
 if p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2) then raise exception 'Informe um valor positivo com até duas casas decimais';end if;
 select coalesce(sum(s.amount),0),array_agg(s.id order by s.paid_on,s.created_at) into paid,ids from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 select coalesce(sum(r.amount),0) into issued from public.payment_receipts r where r.quote_id=q.id and r.kind='payment' and not exists(select 1 from unnest(r.settlement_ids) sid where not exists(select 1 from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where s.id=sid and not s.reversed and not e.voided));
 if p_amount>paid-issued then raise exception 'O recibo supera o recebimento disponível. Recebido: %, já documentado: %',paid,issued;end if;
 select data into config from public.settings where user_id=q.user_id;config:=coalesce(config,'{}'::jsonb);
 company:=jsonb_build_object('company',config->>'company','contact',config->>'contact','logo',config->>'logo','signature',config->>'signature','signature_name',config->>'signature_name','signature_invert',config->'signature_invert','city',config->>'city');
 message:=coalesce(nullif(trim(p_message),''),nullif(config->'budget'->>'receipt_message',''),'Agradecemos o adiantamento e a confiança na Avelon Têxtil. Seu pedido seguirá para o corte da malha, a personalização prevista no orçamento e a costura. Cada etapa será realizada com atenção aos detalhes, cuidado nos acabamentos e compromisso com a qualidade. Manteremos você informado até a conclusão.');
 if length(message)>5000 then raise exception 'O texto do recibo pode ter até 5.000 caracteres';end if;
 select x->>'label' into stage_label from jsonb_array_elements(coalesce(config->'production'->'stages',public.default_stages())) x where x->>'key'=q.stage;
 insert into public.payment_receipts(quote_id,amount,settlement_ids,request_id,snapshot) values(q.id,p_amount,ids,p_request,jsonb_build_object('company',company,'client',q.client_snapshot,'quote_number',q.number,'quote_total',q.total,'agreed_entry_amount',q.production->'agreed_entry_amount','received_total',paid,'remaining',greatest(0,q.total-paid),'stage',coalesce(stage_label,q.stage),'technique',q.production->>'technique','delivery_date',q.delivery_date,'message',message,'title',coalesce(config->'budget'->>'receipt_title','Recibo de adiantamento'),'show_logo',coalesce((config->'budget'->>'receipt_show_logo')::boolean,true),'show_signature',coalesce((config->'budget'->>'receipt_show_signature')::boolean,true),'items',coalesce((select jsonb_agg(jsonb_build_object('description',i.description,'quantity',i.quantity,'details',i.details) order by i.id) from public.quote_items i where i.quote_id=q.id),'[]'::jsonb))) returning id into r;
 insert into public.fin_audit(object_id,action,detail) values(r,'receipt_issued',jsonb_build_object('quote_id',q.id,'amount',p_amount));return r;
end $$;

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


create or replace function public.list_payment_receipts(p_quote uuid default null) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$ begin
 perform public.require_permission('receipts','view');
 return coalesce((select jsonb_agg(jsonb_build_object('kind',r.kind,'id',r.id,'number',r.number,'quote_id',r.quote_id,'amount',r.amount,'created_at',r.created_at,'reversed',public.receipt_is_reversed(r.id)) order by r.created_at desc) from public.payment_receipts r where r.user_id=public.workspace_owner() and (p_quote is null or r.quote_id=p_quote)),'[]'::jsonb);
end $$;

commit;
