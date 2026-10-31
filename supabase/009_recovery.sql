begin;
create or replace function public.create_quote(p_client uuid,p_method text,p_percentage numeric,p_valid_until date,p_notes text,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=public.workspace_owner(); c public.clients; p public.products; q uuid; j jsonb; qty integer; price numeric; total_price numeric:=0;
begin
 perform public.require_permission('quotes','create');perform public.require_permission('clients','view');perform public.require_permission('products','view');
 if u is null then raise exception 'Acesso não autorizado'; end if;
 if p_method not in ('markup','margin') or p_method is null or p_percentage is null or p_percentage<0 or p_percentage>9999 or (p_method='margin' and p_percentage>=100) then raise exception 'Percentual inválido'; end if;
 if p_valid_until is null then raise exception 'Informe a validade'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Informe de 1 a 100 itens'; end if;
 select * into c from public.clients where id=p_client and user_id=u;
 if not found then raise exception 'Cliente não encontrado'; end if;
 insert into public.quotes(user_id,client_id,client_snapshot,method,percentage,notes,valid_until,total)
 values(u,c.id,jsonb_build_object('name',c.name,'kind',c.kind,'document',c.document,'phone',c.phone,'email',c.email,'address',c.address),p_method,p_percentage,coalesce(p_notes,''),p_valid_until,0) returning id into q;
 for j in select * from jsonb_array_elements(p_items) loop
  select * into p from public.products where id=(j->>'product_id')::uuid and user_id=u;
  if not found then raise exception 'Produto não encontrado'; end if;
  qty:=(j->>'quantity')::integer;
  if qty is null or qty not between 1 and 100000 then raise exception 'Quantidade inválida'; end if;
  price:=round(case when p_method='markup' then p.cost*(1+p_percentage/100) else p.cost/(1-p_percentage/100) end,2);
  insert into public.quote_items(user_id,quote_id,product_id,description,quantity,cost_snapshot,unit_price,details)
  values(u,q,p.id,p.name,qty,p.cost,price,coalesce(j->>'details',''));
  total_price:=total_price+price*qty;
 end loop;
 update public.quotes set total=total_price where id=q;
 return q;
end $$;
revoke all on function public.create_quote(uuid,text,numeric,date,text,jsonb) from public;
grant execute on function public.create_quote(uuid,text,numeric,date,text,jsonb) to authenticated;

create or replace function public.prepare_receivables(p_quote uuid,p_first_due date,p_final_due date) returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;deposit numeric;n integer:=0;k integer;begin
 perform public.require_permission('finance','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 if q.stage in ('cancelled','suspended') then raise exception 'Pedido cancelado ou suspenso não pode gerar parcelas';end if;
 if p_first_due is null or p_final_due is null or p_final_due<p_first_due then raise exception 'Verifique os vencimentos';end if;
 deposit:=round(q.total*q.entry_percentage/100,2);
 if deposit>0 then insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence,quote_id,installment) values('income','revenue','Vendas','Pedido #'||q.number||' · entrada',q.client_snapshot->>'name',deposit,p_first_due,(q.created_at at time zone 'America/Sao_Paulo')::date,q.id,1) on conflict(quote_id,installment) do nothing;get diagnostics k=row_count;n:=n+k;end if;
 if q.total-deposit>0 then insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence,quote_id,installment) values('income','revenue','Vendas','Pedido #'||q.number||' · saldo',q.client_snapshot->>'name',q.total-deposit,p_final_due,(q.created_at at time zone 'America/Sao_Paulo')::date,q.id,2) on conflict(quote_id,installment) do nothing;get diagnostics k=row_count;n:=n+k;end if;
 insert into public.fin_audit(object_id,action,detail) values(q.id,'receivables_prepared',jsonb_build_object('created',n));return n;end $$;

create or replace function public.restore_bank_line(p_line uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 perform public.require_permission('bank','reconcile');
 update public.bank_lines set status='pending',ignore_reason='' where id=p_line and user_id=public.workspace_owner() and status='ignored';
 if not found then raise exception 'Somente movimentos ignorados podem ser reabertos';end if;
 insert into public.fin_audit(object_id,action) values(p_line,'bank_restored');
end $$;
create or replace function public.restore_fin_entry(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public,pg_temp as $$ declare e public.fin_entries;begin
 perform public.require_permission('finance','edit');if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Informe o motivo da reativação';end if;
 select * into e from public.fin_entries where id=p_id and user_id=public.workspace_owner() for update;
 if not found or not e.voided or e.transfer_group is not null then raise exception 'Título indisponível para reativação';end if;
 if e.quote_id is not null and exists(select 1 from public.quotes where id=e.quote_id and stage in('cancelled','suspended')) then raise exception 'Retome o pedido antes de reativar as parcelas';end if;
 update public.fin_entries set voided=false,void_reason='' where id=e.id;
 insert into public.fin_audit(object_id,action,detail) values(e.id,'entry_restored',jsonb_build_object('reason',p_reason));
end $$;
revoke all on function public.restore_bank_line(uuid),public.restore_fin_entry(uuid,text) from public;
grant execute on function public.restore_bank_line(uuid),public.restore_fin_entry(uuid,text) to authenticated;
create or replace function public.reconcile_bank_line(p_line uuid,p_entry uuid,p_settlement uuid,p_new jsonb,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare b public.bank_lines;e public.fin_entries;s public.fin_settlements;r uuid;paid numeric;begin
 perform public.require_permission('bank','reconcile');
 select * into b from public.bank_lines where id=p_line and user_id=public.workspace_owner() for update;if not found or b.status<>'pending' then raise exception 'Linha já conciliada ou indisponível';end if;
 if p_settlement is not null then
  select * into s from public.fin_settlements where id=p_settlement and user_id=b.user_id for update;
  if not found or s.reversed or s.statement_id is not null or s.account_id<>b.account_id or s.amount<>abs(b.amount) then raise exception 'A baixa escolhida não corresponde ao extrato';end if;
  select * into e from public.fin_entries where id=s.entry_id;
  if (e.kind='income')<>(b.amount>0) then raise exception 'Sentidos de movimentação diferentes';end if;
  update public.fin_settlements set statement_id=b.id,bank_date=b.posted_on where id=s.id;r:=s.id;
 else
  if not exists(select 1 from public.bank_accounts where id=b.account_id and active) then raise exception 'Ative a conta antes de registrar uma nova baixa';end if;
  if p_entry is null then
   perform public.require_permission('finance','create');
   insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence) values(case when b.amount>0 then 'income' else 'expense' end,p_new->>'class',p_new->>'category',b.description,coalesce(p_new->>'party',''),abs(b.amount),b.posted_on,b.posted_on) returning * into e;
  else select * into e from public.fin_entries where id=p_entry and user_id=b.user_id for update;end if;
  if e.id is null or e.voided or (e.kind='income')<>(b.amount>0) then raise exception 'Lançamento não corresponde à linha';end if;
  select coalesce(sum(amount),0) into paid from public.fin_settlements where entry_id=e.id and not reversed;
  if abs(b.amount)>e.amount-paid then raise exception 'O valor do extrato supera o saldo pendente';end if;
  insert into public.fin_settlements(entry_id,account_id,amount,paid_on,bank_date,memo,statement_id,request_id) values(e.id,b.account_id,abs(b.amount),b.posted_on,b.posted_on,'Conciliação bancária',b.id,p_request) returning id into r;
 end if;
 update public.bank_lines set status='matched' where id=b.id;
 insert into public.fin_audit(object_id,action,detail) values(b.id,'bank_reconciled',jsonb_build_object('settlement_id',r));return r;end $$;

commit;
