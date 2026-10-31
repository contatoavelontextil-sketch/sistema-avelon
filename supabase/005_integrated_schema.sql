begin;
-- An approved company member sees only the company workspace and granted modules.
create function public.workspace_owner() returns uuid language sql stable security definer set search_path=public,pg_temp as $$
 select id from public.profiles where is_owner and active order by created_at limit 1
$$;
revoke all on function public.workspace_owner() from public;
grant execute on function public.workspace_owner() to authenticated;
alter table public.clients alter column user_id set default public.workspace_owner();
alter table public.products alter column user_id set default public.workspace_owner();
drop policy own_clients on public.clients;
drop policy own_products on public.products;
drop policy own_quotes on public.quotes;
drop policy own_items on public.quote_items;
create policy own_clients on public.clients for all to authenticated using(user_id=public.workspace_owner()) with check(user_id=public.workspace_owner());
create policy own_products on public.products for all to authenticated using(user_id=public.workspace_owner()) with check(user_id=public.workspace_owner());
create policy own_quotes on public.quotes for select to authenticated using(user_id=public.workspace_owner());
create policy own_items on public.quote_items for select to authenticated using(user_id=public.workspace_owner());
drop policy own_settings on public.settings;
create policy own_settings on public.settings for select to authenticated using(user_id=public.workspace_owner() and public.is_active());
alter table public.quotes add column stage text not null default 'draft',add column delivery_date date,add column entry_percentage numeric(5,2) not null default 50 check(entry_percentage between 0 and 100),add column production jsonb not null default '{}',add column updated_at timestamptz not null default now();
create table public.quote_events(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),quote_id uuid not null references public.quotes(id),actor_id uuid not null references auth.users(id),previous_stage text,next_stage text not null,note text not null default '',created_at timestamptz not null default now());
create table public.bank_accounts(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),name text not null check(length(trim(name)) between 2 and 150),opening_balance numeric(14,2) not null default 0,opening_date date not null default current_date,active boolean not null default true,created_at timestamptz not null default now(),unique(id,user_id));
create table public.fin_entries(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),kind text not null check(kind in ('income','expense')),class text not null check(class in ('revenue','cost','expense','asset','equity','transfer','tax','other')),category text not null,description text not null check(length(trim(description)) between 2 and 1000),party text not null default '',amount numeric(14,2) not null check(amount>0),due_date date not null,competence date not null,quote_id uuid,installment integer,recurring_id uuid,voided boolean not null default false,void_reason text not null default '',created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),foreign key(quote_id,user_id) references public.quotes(id,user_id),unique(quote_id,installment),unique(recurring_id,due_date),unique(id,user_id));
create table public.bank_imports(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),account_id uuid not null,file_name text not null,file_hash text not null,imported_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),foreign key(account_id,user_id) references public.bank_accounts(id,user_id));
create table public.bank_lines(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),account_id uuid not null,import_id uuid not null references public.bank_imports(id),external_id text not null check(length(external_id) between 1 and 300),posted_on date not null,description text not null,amount numeric(14,2) not null check(amount<>0),status text not null default 'pending' check(status in ('pending','matched','ignored')),ignore_reason text not null default '',created_at timestamptz not null default now(),foreign key(account_id,user_id) references public.bank_accounts(id,user_id),unique(account_id,external_id),unique(id,user_id));
create table public.fin_settlements(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),entry_id uuid not null,account_id uuid not null,amount numeric(14,2) not null check(amount>0),paid_on date not null,bank_date date,memo text not null default '',statement_id uuid unique,request_id uuid not null unique,created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),reversed boolean not null default false,reversal_reason text not null default '',foreign key(entry_id,user_id) references public.fin_entries(id,user_id),foreign key(account_id,user_id) references public.bank_accounts(id,user_id),foreign key(statement_id,user_id) references public.bank_lines(id,user_id));
create table public.recurring_expenses(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),description text not null,category text not null,class text not null check(class in ('cost','expense','tax')),amount numeric(14,2) not null check(amount>0),due_day integer not null check(due_day between 1 and 31),starts_on date not null,ends_on date,active boolean not null default true,created_at timestamptz not null default now());
alter table public.fin_entries add foreign key(recurring_id) references public.recurring_expenses(id);
create table public.company_assets(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),name text not null,acquired_on date not null,cost numeric(14,2) not null check(cost>0),residual numeric(14,2) not null default 0 check(residual>=0 and residual<=cost),life_months integer not null check(life_months between 1 and 1200),notes text not null default '',active boolean not null default true,created_at timestamptz not null default now());
create table public.fin_audit(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),actor_id uuid not null default auth.uid() references auth.users(id),object_id uuid,action text not null,detail jsonb not null default '{}',created_at timestamptz not null default now());
create index on public.fin_entries(user_id,due_date);
create index on public.fin_settlements(user_id,entry_id);
create index on public.bank_lines(user_id,account_id,posted_on);
create index on public.quote_events(user_id,quote_id);
create index on public.fin_audit(user_id,created_at);
do $$ declare t text;r text;begin
 foreach t in array array['quote_events','bank_accounts','fin_entries','bank_imports','bank_lines','fin_settlements','recurring_expenses','company_assets','fin_audit'] loop
  execute format('alter table public.%I enable row level security',t);
  r:=case when t='quote_events' then 'workflow' when t in ('bank_lines','bank_imports') then 'bank' when t='company_assets' then 'assets' else 'finance' end;
  execute format('create policy workspace_read on public.%I for select to authenticated using(user_id=public.workspace_owner() and (public.can(%L,''view'') or public.can(''reports'',''view'')))',t,r);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
create function public.require_permission(p_resource text,p_action text) returns void language plpgsql security definer set search_path=public,pg_temp as $$ begin
 if not public.can(p_resource,p_action) or public.workspace_owner() is null then raise exception 'Sem permissão: %.%',p_resource,p_action;end if;
end $$;
revoke all on function public.require_permission(text,text) from public;
grant execute on function public.require_permission(text,text) to authenticated;
create function public.default_stages() returns jsonb language sql immutable as $$ select '[{"key":"draft","label":"Rascunho","color":"#64748b"},{"key":"sent","label":"Enviado","color":"#3b82f6"},{"key":"awaiting_deposit","label":"Aguardando entrada","color":"#f59e0b"},{"key":"production","label":"Em produção","color":"#8b5cf6"},{"key":"cutting","label":"Corte","color":"#7c3aed"},{"key":"personalization","label":"Personalização","color":"#db2777"},{"key":"ready","label":"Pedido pronto","color":"#0891b2"},{"key":"awaiting_balance","label":"Aguardando saldo","color":"#d97706"},{"key":"completed","label":"Finalizado","color":"#16a34a"},{"key":"suspended","label":"Suspenso","color":"#64748b"},{"key":"cancelled","label":"Cancelado","color":"#dc2626"}]'::jsonb $$;
revoke all on function public.default_stages() from public;
grant execute on function public.default_stages() to authenticated;
commit;
