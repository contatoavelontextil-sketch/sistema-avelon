begin;
create function public.mark_ready_message_action(p_quote uuid,p_channel text,p_message text,p_expected timestamptz) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;begin
 perform public.require_permission('workflow','edit');
 if p_channel is null or p_channel not in ('copy','share') or length(trim(coalesce(p_message,''))) not between 1 and 5000 then raise exception 'Mensagem ou ação inválida';end if;
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;
 if not found then raise exception 'Pedido não encontrado';end if;
 if q.superseded_by is not null then raise exception 'Abra a revisão atual deste pedido';end if;
 if q.stage='awaiting_balance' then return jsonb_build_object('stage',q.stage,'changed',false);end if;
 if q.stage<>'ready' then raise exception 'O pedido precisa estar em Pedido pronto. Atualize o quadro antes de continuar';end if;
 perform public.update_order(q.id,'awaiting_balance',q.delivery_date,q.production||jsonb_build_object('ready_client_message',p_message,'ready_message_action',p_channel,'ready_message_action_at',clock_timestamp()),case when p_channel='copy' then 'Mensagem de pedido pronto copiada pelo usuário; aguardando confirmação do saldo.' else 'Compartilhamento da mensagem de pedido pronto concluído pelo usuário; aguardando confirmação do saldo.' end,p_expected);
 return jsonb_build_object('stage','awaiting_balance','changed',true);
end $$;
revoke all on function public.mark_ready_message_action(uuid,text,text,timestamptz) from public;
grant execute on function public.mark_ready_message_action(uuid,text,text,timestamptz) to authenticated;
create or replace function public.issue_final_receipt(p_quote uuid,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
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
 'order_history',(select coalesce(jsonb_agg(to_jsonb(h) order by h.event_at,h.sort_order),'[]'::jsonb) from (
 select v.created_at as event_at,0 as sort_order,'Orçamento emitido'::text as stage_label,''::text as previous_label,
 'Emissão '||case when v.revision_no=0 then 'da versão inicial' else 'da Rev. '||lpad(v.revision_no::text,2,'0') end as note,
 lpad(v.base_number::text,greatest(4,length(v.base_number::text)),'0')||case when v.revision_no>0 then ' Rev. '||lpad(v.revision_no::text,2,'0') else '' end as quote_reference
 from public.quotes v where coalesce(v.revision_root,v.id)=coalesce(q.revision_root,q.id) and v.user_id=q.user_id
 union all
 select e.created_at,1,
 coalesce((select x->>'label' from jsonb_array_elements(coalesce(cfg->'production'->'stages',public.default_stages())) x where x->>'key'=e.next_stage limit 1),e.next_stage),
 coalesce((select x->>'label' from jsonb_array_elements(coalesce(cfg->'production'->'stages',public.default_stages())) x where x->>'key'=e.previous_stage limit 1),e.previous_stage,''),
 case when e.next_stage in ('cancelled','suspended','awaiting_balance','completed') then e.note else '' end,
 lpad(v.base_number::text,greatest(4,length(v.base_number::text)),'0')||case when v.revision_no>0 then ' Rev. '||lpad(v.revision_no::text,2,'0') else '' end
 from public.quote_events e join public.quotes v on v.id=e.quote_id where coalesce(v.revision_root,v.id)=coalesce(q.revision_root,q.id) and e.user_id=q.user_id
 ) h),
 'message',coalesce(nullif(cfg->'budget'->>'final_receipt_message',''),'Agradecemos a confiança na Avelon Têxtil. Seu pedido foi concluído e os pagamentos foram integralmente confirmados. Foi um prazer cuidar de cada etapa da produção. Esperamos fazer parte dos seus próximos projetos.'),
 'title',coalesce(nullif(cfg->'budget'->>'final_receipt_title',''),'Recibo final de quitação'),'show_logo',coalesce((cfg->'budget'->>'receipt_show_logo')::boolean,true),'show_signature',coalesce((cfg->'budget'->>'receipt_show_signature')::boolean,true),
 'items',coalesce((select jsonb_agg(jsonb_build_object('description',i.description,'quantity',i.quantity,'details',i.details) order by i.id) from public.quote_items i where i.quote_id=q.id),'[]'::jsonb))) returning id into result_id;
 insert into public.fin_audit(object_id,action,detail) values(result_id,'final_receipt_issued',jsonb_build_object('quote_id',q.id,'total',paid));return result_id;
end $$;
commit;
