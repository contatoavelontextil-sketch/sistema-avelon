begin;
create or replace function public.snapshot_company() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$ begin
 perform public.require_permission('quotes','create');perform public.require_permission('clients','view');perform public.require_permission('products','view');
 select coalesce(data,'{}'::jsonb) into new.company_snapshot from public.settings where user_id=public.workspace_owner();
 new.company_snapshot:=coalesce(new.company_snapshot,'{}'::jsonb);
 new.entry_percentage:=coalesce((new.company_snapshot->'budget'->>'deposit_percentage')::numeric,50);
 return new;end $$;
create or replace function public.save_settings(p_data jsonb) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare old jsonb;k text;r text;s jsonb;u uuid:=public.workspace_owner();begin
 if not public.is_active() or u is null then raise exception 'Acesso não autorizado';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>1500000 then raise exception 'Configurações inválidas ou imagens muito grandes';end if;
 select data into old from public.settings where user_id=u for update;old:=coalesce(old,'{}'::jsonb);
 for k in select jsonb_object_keys(p_data) loop
  if (p_data->k) is distinct from (old->k) then
   r:=case when k in ('company','contact','logo','signature','signature_name','signature_invert','city') then 'settings_company' when k in ('method','percentage','valid_days','conditions','budget') then 'settings_quotes' when k in ('accent','appearance') then 'settings_appearance' when k='production' then 'settings_production' when k='finance' then 'settings_finance' when k='reports' then 'settings_reports' else null end;
   if r is null then raise exception 'Configuração desconhecida: %',k;end if;perform public.require_permission(r,'edit');
  end if;
 end loop;
 if p_data?'production' and p_data->'production'?'stages' then
  s:=p_data->'production'->'stages';
  if jsonb_typeof(s)<>'array' or jsonb_array_length(s) not between 3 and 30 then raise exception 'Defina de 3 a 30 etapas';end if;
  if exists(select 1 from jsonb_array_elements(s) a where a->>'key' !~ '^[a-z][a-z0-9_]{1,31}$' or length(a->>'label') not between 2 and 60 or a->>'color' !~ '^#[A-Fa-f0-9]{6}$') then raise exception 'Identificação, nome ou cor de etapa inválida';end if;
  if (select count(*) from jsonb_array_elements(s))<>(select count(distinct a->>'key') from jsonb_array_elements(s) a) then raise exception 'As etapas devem ter identificações únicas';end if;
  if not exists(select 1 from jsonb_array_elements(s) a where a->>'key'='draft') or not exists(select 1 from jsonb_array_elements(s) a where a->>'key'='completed') then raise exception 'Preserve as etapas Rascunho e Finalizado';end if;
  if exists(select 1 from public.quotes q where q.user_id=u and not exists(select 1 from jsonb_array_elements(s) a where a->>'key'=q.stage)) then raise exception 'Não remova uma etapa que contém pedidos';end if;
 end if;
 if p_data?'budget' and (p_data->'budget'->>'deposit_percentage')::numeric not between 0 and 100 then raise exception 'Entrada deve ficar entre 0%% e 100%%';end if;
 if p_data?'logo' and length(p_data->>'logo')>0 and p_data->>'logo' !~ '^data:image/(png|jpeg|webp);base64,' then raise exception 'Envie uma imagem válida para a logo';end if;
 if p_data?'signature' and length(p_data->>'signature')>0 and p_data->>'signature' !~ '^data:image/(png|jpeg|webp);base64,' then raise exception 'Envie uma imagem válida para a assinatura';end if;
 if p_data?'accent' and p_data->>'accent' !~ '^#[A-Fa-f0-9]{6}$' then raise exception 'Cor de destaque inválida';end if;
 if p_data?'method' and p_data->>'method' not in ('margin','markup') then raise exception 'Método de cálculo inválido';end if;
 if p_data?'percentage' and ((p_data->>'percentage')::numeric not between 0 and 9999 or coalesce(p_data->>'method',old->>'method')='margin' and (p_data->>'percentage')::numeric>=100) then raise exception 'Percentual inválido';end if;
 if p_data?'budget' then
  s:=p_data->'budget';if (s->>'production_days')::integer not between 1 and 365 or (s->>'validity_days')::integer not between 1 and 365 or length(s->>'important_notes')>20000 then raise exception 'Prazo ou orientações inválidas';end if;
 end if;
 if p_data?'finance' then
  s:=p_data->'finance';if (s->>'reconcile_days')::integer not between 0 and 30 or (s->>'default_life_months')::integer not between 1 and 1200 or s->>'csv_separator' not in (';',',',E'\t') or (s->>'csv_date')::integer not between 0 and 99 or (s->>'csv_description')::integer not between 0 and 99 or (s->>'csv_amount')::integer not between 0 and 99 or (s->>'csv_id')::integer not between -1 and 99 then raise exception 'Configuração financeira inválida';end if;
  if jsonb_typeof(s->'categories')<>'array' or jsonb_array_length(s->'categories') not between 1 and 200 or jsonb_typeof(s->'partners')<>'array' or jsonb_array_length(s->'partners')>100 or jsonb_typeof(s->'payment_methods')<>'array' or jsonb_array_length(s->'payment_methods') not between 1 and 100 then raise exception 'Preencha as categorias e formas de pagamento';end if;
 end if;
 if p_data?'reports' and p_data->'reports'->>'basis' not in ('cash','accrual') then raise exception 'Regime inválido';end if;
 if p_data?'appearance' and (p_data->'appearance'->>'density' not in ('comfortable','compact') or jsonb_typeof(p_data->'appearance'->'menu')<>'array') then raise exception 'Aparência inválida';end if;
 insert into public.settings(user_id,data) values(u,old||p_data) on conflict(user_id) do update set data=excluded.data,updated_at=now();
end $$;
alter table public.settings drop constraint settings_data_check;
alter table public.settings add constraint settings_data_check check(octet_length(data::text)<1500000);
create function public.create_quote_v2(p_client uuid,p_method text,p_percentage numeric,p_valid_until date,p_notes text,p_items jsonb,p_meta jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$ declare q uuid;begin
 q:=public.create_quote(p_client,p_method,p_percentage,p_valid_until,p_notes,p_items);
 update public.quotes set delivery_date=nullif(p_meta->>'delivery_date','')::date,entry_percentage=coalesce((p_meta->>'entry_percentage')::numeric,entry_percentage),production=jsonb_build_object('technique',coalesce(p_meta->>'technique',''),'specifications',coalesce(p_meta->>'specifications',''),'art_approved',false) where id=q;
 return q;
end $$;
create function public.update_order(p_quote uuid,p_stage text,p_delivery date,p_production jsonb,p_note text,p_expected timestamptz) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;c jsonb;s jsonb;paid numeric;begin
 perform public.require_permission('workflow','edit');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 if p_expected is not null and q.updated_at<>p_expected then raise exception 'O pedido foi alterado. Atualize o quadro antes de salvar';end if;
 select data into c from public.settings where user_id=q.user_id;c:=coalesce(c,'{}'::jsonb);s:=coalesce(c->'production'->'stages',public.default_stages());
 if not exists(select 1 from jsonb_array_elements(s) x where x->>'key'=p_stage and coalesce((x->>'enabled')::boolean,true)) then raise exception 'Etapa não disponível';end if;
 select coalesce(sum(s.amount),0) into paid from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q.id and not s.reversed and not e.voided;
 if coalesce((c->'production'->>'require_deposit')::boolean,true) and p_stage in ('production','cutting','personalization','ready') and paid<round(q.total*q.entry_percentage/100,2) then raise exception 'Registre a entrada acordada antes de iniciar a produção';end if;
 if coalesce((c->'production'->>'require_art')::boolean,true) and p_stage in ('production','cutting','personalization','ready') and not coalesce((p_production->>'art_approved')::boolean,false) then raise exception 'Confirme a aprovação da arte antes da produção';end if;
 if coalesce((c->'production'->>'require_balance')::boolean,true) and p_stage='completed' and paid<q.total then raise exception 'Ainda existe saldo a receber neste pedido';end if;
 if p_stage in ('cancelled','suspended') and length(trim(coalesce(p_note,'')))<3 then raise exception 'Informe o motivo do cancelamento ou suspensão';end if;
 update public.quotes set stage=p_stage,delivery_date=p_delivery,production=coalesce(p_production,'{}'::jsonb),updated_at=now() where id=q.id;
 insert into public.quote_events(user_id,quote_id,actor_id,previous_stage,next_stage,note) values(q.user_id,q.id,auth.uid(),q.stage,p_stage,coalesce(p_note,''));
end $$;
create function public.save_account(p_id uuid,p_name text,p_opening numeric,p_date date,p_active boolean) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$ declare r uuid;begin
 perform public.require_permission('settings_finance','edit');
 if p_id is null then insert into public.bank_accounts(name,opening_balance,opening_date,active) values(p_name,p_opening,p_date,p_active) returning id into r;
 else update public.bank_accounts set name=p_name,opening_balance=p_opening,opening_date=p_date,active=p_active where id=p_id and user_id=public.workspace_owner() returning id into r;end if;
 if r is null then raise exception 'Conta não encontrada';end if;
 insert into public.fin_audit(object_id,action,detail) values(r,'account_saved',jsonb_build_object('name',p_name));return r;end $$;
create function public.save_fin_entry(p_id uuid,p_kind text,p_class text,p_category text,p_description text,p_party text,p_amount numeric,p_due date,p_competence date) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare e public.fin_entries;r uuid;begin
 perform public.require_permission('finance',case when p_id is null then 'create' else 'edit' end);
 if p_id is null then insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence) values(p_kind,p_class,p_category,p_description,p_party,p_amount,p_due,p_competence) returning id into r;
 else
 select * into e from public.fin_entries where id=p_id and user_id=public.workspace_owner() for update;if not found then raise exception 'Lançamento não encontrado';end if;
 if e.quote_id is not null or exists(select 1 from public.fin_settlements where entry_id=e.id and not reversed) then raise exception 'Preserve lançamentos vinculados ou com baixa. Use estorno e novo lançamento';end if;
 update public.fin_entries set kind=p_kind,class=p_class,category=p_category,description=p_description,party=p_party,amount=p_amount,due_date=p_due,competence=p_competence where id=e.id returning id into r;end if;
 insert into public.fin_audit(object_id,action,detail) values(r,'entry_saved',jsonb_build_object('amount',p_amount,'kind',p_kind));return r;end $$;
create function public.prepare_receivables(p_quote uuid,p_first_due date,p_final_due date) returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare q public.quotes;deposit numeric;n integer:=0;k integer;begin
 perform public.require_permission('finance','create');
 select * into q from public.quotes where id=p_quote and user_id=public.workspace_owner() for update;if not found then raise exception 'Pedido não encontrado';end if;
 if q.stage in ('cancelled','suspended') then raise exception 'Pedido cancelado ou suspenso não pode gerar parcelas';end if;
 if p_first_due is null or p_final_due is null or p_final_due<p_first_due then raise exception 'Verifique os vencimentos';end if;
 deposit:=round(q.total*q.entry_percentage/100,2);
 if deposit>0 then insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence,quote_id,installment) values('income','revenue','Vendas','Pedido #'||q.number||' · entrada',q.client_snapshot->>'name',deposit,p_first_due,q.created_at::date,q.id,1) on conflict(quote_id,installment) do nothing;get diagnostics k=row_count;n:=n+k;end if;
 if q.total-deposit>0 then insert into public.fin_entries(kind,class,category,description,party,amount,due_date,competence,quote_id,installment) values('income','revenue','Vendas','Pedido #'||q.number||' · saldo',q.client_snapshot->>'name',q.total-deposit,p_final_due,q.created_at::date,q.id,2) on conflict(quote_id,installment) do nothing;get diagnostics k=row_count;n:=n+k;end if;
 insert into public.fin_audit(object_id,action,detail) values(q.id,'receivables_prepared',jsonb_build_object('created',n));return n;end $$;
create function public.settle_entry(p_entry uuid,p_account uuid,p_amount numeric,p_date date,p_memo text,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare e public.fin_entries;paid numeric;r uuid;begin
 perform public.require_permission('finance','settle');
 select id into r from public.fin_settlements where request_id=p_request and user_id=public.workspace_owner();if r is not null then return r;end if;
 select * into e from public.fin_entries where id=p_entry and user_id=public.workspace_owner() for update;if not found or e.voided then raise exception 'Lançamento indisponível';end if;
 if not exists(select 1 from public.bank_accounts where id=p_account and user_id=e.user_id and active) then raise exception 'Selecione uma conta ativa';end if;
 select coalesce(sum(amount),0) into paid from public.fin_settlements where entry_id=e.id and not reversed;
 if p_amount is null or p_amount<=0 or round(p_amount,2)>e.amount-paid then raise exception 'O valor supera o saldo pendente ou é inválido';end if;
 insert into public.fin_settlements(entry_id,account_id,amount,paid_on,memo,request_id) values(e.id,p_account,round(p_amount,2),p_date,coalesce(p_memo,''),p_request) returning id into r;
 insert into public.fin_audit(object_id,action,detail) values(r,'settled',jsonb_build_object('entry_id',e.id,'amount',p_amount));return r;end $$;
create function public.reverse_settlement(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public,pg_temp as $$ declare s public.fin_settlements;begin
 perform public.require_permission('finance','reverse');if length(trim(p_reason))<3 then raise exception 'Informe o motivo do estorno';end if;
 select * into s from public.fin_settlements where id=p_id and user_id=public.workspace_owner() for update;if not found or s.reversed then raise exception 'Baixa indisponível';end if;
 if s.statement_id is not null then update public.bank_lines set status='pending' where id=s.statement_id;end if;
 update public.fin_settlements set reversed=true,reversal_reason=p_reason,statement_id=null where id=s.id;
 insert into public.fin_audit(object_id,action,detail) values(s.id,'reversed',jsonb_build_object('reason',p_reason));end $$;
create function public.void_fin_entry(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public,pg_temp as $$ declare e public.fin_entries;begin
 perform public.require_permission('finance','delete');if length(trim(p_reason))<3 then raise exception 'Informe um motivo';end if;
 select * into e from public.fin_entries where id=p_id and user_id=public.workspace_owner() for update;if not found then raise exception 'Lançamento não encontrado';end if;
 if exists(select 1 from public.fin_settlements where entry_id=e.id and not reversed) then raise exception 'Estorne as baixas antes de cancelar o lançamento';end if;
 update public.fin_entries set voided=true,void_reason=p_reason where id=e.id;
 insert into public.fin_audit(object_id,action,detail) values(e.id,'entry_voided',jsonb_build_object('reason',p_reason));end $$;
create function public.import_bank_lines(p_account uuid,p_name text,p_hash text,p_lines jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare imp uuid;j jsonb;n integer:=0;k integer;begin
 perform public.require_permission('bank','import');
 if not exists(select 1 from public.bank_accounts where id=p_account and user_id=public.workspace_owner() and active) then raise exception 'Selecione uma conta ativa';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 1 and 5000 then raise exception 'Importe de 1 a 5.000 linhas por arquivo';end if;
 insert into public.bank_imports(account_id,file_name,file_hash) values(p_account,p_name,p_hash) returning id into imp;
 for j in select * from jsonb_array_elements(p_lines) loop
  insert into public.bank_lines(account_id,import_id,external_id,posted_on,description,amount) values(p_account,imp,j->>'external_id',(j->>'date')::date,left(j->>'description',2000),(j->>'amount')::numeric) on conflict(account_id,external_id) do nothing;get diagnostics k=row_count;n:=n+k;
 end loop;
 insert into public.fin_audit(object_id,action,detail) values(imp,'bank_imported',jsonb_build_object('rows',n,'duplicates',jsonb_array_length(p_lines)-n));return jsonb_build_object('imported',n,'duplicates',jsonb_array_length(p_lines)-n);end $$;
create function public.reconcile_bank_line(p_line uuid,p_entry uuid,p_settlement uuid,p_new jsonb,p_request uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
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
create function public.ignore_bank_line(p_line uuid,p_reason text) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 perform public.require_permission('bank','reconcile');if length(trim(p_reason))<3 then raise exception 'Informe um motivo';end if;
 update public.bank_lines set status='ignored',ignore_reason=p_reason where id=p_line and user_id=public.workspace_owner() and status='pending';if not found then raise exception 'Linha indisponível';end if;
 insert into public.fin_audit(object_id,action,detail) values(p_line,'bank_ignored',jsonb_build_object('reason',p_reason));end $$;
create function public.save_recurring(p_id uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$ declare r uuid;begin
 perform public.require_permission('finance','edit');
 if p_id is null then insert into public.recurring_expenses(description,category,class,amount,due_day,starts_on,ends_on) values(p_data->>'description',p_data->>'category',p_data->>'class',(p_data->>'amount')::numeric,(p_data->>'due_day')::integer,(p_data->>'starts_on')::date,nullif(p_data->>'ends_on','')::date) returning id into r;
 else update public.recurring_expenses set active=(p_data->>'active')::boolean where id=p_id and user_id=public.workspace_owner() returning id into r;end if;
 if r is null then raise exception 'Recorrência não encontrada';end if;return r;end $$;
create function public.generate_recurring(p_month date,p_months integer) returns integer language plpgsql security definer set search_path=public,pg_temp as $$ declare t public.recurring_expenses;m date;d date;i integer;n integer:=0;k integer;begin
 perform public.require_permission('finance','create');if p_months not between 1 and 12 then raise exception 'Gere de 1 a 12 meses';end if;
 for t in select * from public.recurring_expenses where user_id=public.workspace_owner() and active loop
  for i in 0..p_months-1 loop
   m:=(date_trunc('month',p_month)+make_interval(months=>i))::date;d:=m+least(t.due_day-1,extract(day from (m+interval '1 month -1 day'))::integer-1);
   if d>=t.starts_on and (t.ends_on is null or d<=t.ends_on) then insert into public.fin_entries(kind,class,category,description,amount,due_date,competence,recurring_id) values('expense',t.class,t.category,t.description,t.amount,d,m,t.id) on conflict(recurring_id,due_date) do nothing;get diagnostics k=row_count;n:=n+k;end if;
  end loop;
 end loop;return n;end $$;
create function public.save_company_asset(p_id uuid,p_data jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$ declare r uuid;begin
 perform public.require_permission('assets',case when p_id is null then 'create' else 'edit' end);
 if p_id is null then insert into public.company_assets(name,acquired_on,cost,residual,life_months,notes) values(p_data->>'name',(p_data->>'acquired_on')::date,(p_data->>'cost')::numeric,(p_data->>'residual')::numeric,(p_data->>'life_months')::integer,coalesce(p_data->>'notes','')) returning id into r;
 else update public.company_assets set name=p_data->>'name',notes=coalesce(p_data->>'notes',notes),active=coalesce((p_data->>'active')::boolean,active) where id=p_id and user_id=public.workspace_owner() returning id into r;end if;
 if r is null then raise exception 'Ativo não encontrado';end if;return r;end $$;
-- All mutations are RPC-only and authorize the current caller, never a browser service key.
do $$ declare f record;begin
 for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_quote_v2','update_order','save_account','save_fin_entry','prepare_receivables','settle_entry','reverse_settlement','void_fin_entry','import_bank_lines','reconcile_bank_line','ignore_bank_line','save_recurring','generate_recurring','save_company_asset') loop
 execute format('revoke all on function %s from public',f.sig);execute format('grant execute on function %s to authenticated',f.sig);end loop;end $$;
commit;
