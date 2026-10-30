begin;
create table public.clients (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id),
 kind text not null check(kind in ('PF','PJ')), name text not null check(length(trim(name)) between 2 and 200),
 document text not null default '', phone text not null default '', email text not null default '', address text not null default '',
 created_at timestamptz not null default now(), unique(id,user_id)
);
create table public.products (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id),
 name text not null check(length(trim(name)) between 2 and 200), sku text not null default '',
 cost numeric(12,2) not null check(cost>=0), retail numeric(12,2) not null check(retail>=0), wholesale numeric(12,2) not null check(wholesale>=0),
 created_at timestamptz not null default now(), unique(id,user_id)
);
create table public.quotes (
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 user_id uuid not null default auth.uid() references auth.users(id), client_id uuid not null,
 client_snapshot jsonb not null, method text not null check(method in ('markup','margin')), percentage numeric(8,2) not null check(percentage>=0 and (method<>'margin' or percentage<100)),
 notes text not null default '', valid_until date not null, total numeric(14,2) not null check(total>=0),
 created_at timestamptz not null default now(), unique(id,user_id), foreign key(client_id,user_id) references public.clients(id,user_id)
);
create table public.quote_items (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id), quote_id uuid not null,
 product_id uuid not null, description text not null, quantity integer not null check(quantity between 1 and 100000),
 cost_snapshot numeric(12,2) not null check(cost_snapshot>=0), unit_price numeric(12,2) not null check(unit_price>=0),
 details text not null default '', foreign key(quote_id,user_id) references public.quotes(id,user_id), foreign key(product_id,user_id) references public.products(id,user_id)
);
alter table public.clients enable row level security;
alter table public.products enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;
create policy own_clients on public.clients for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy own_products on public.products for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy own_quotes on public.quotes for select to authenticated using(user_id=(select auth.uid()));
create policy own_items on public.quote_items for select to authenticated using(user_id=(select auth.uid()));
grant usage on schema public to authenticated;
grant select,insert,update on public.clients,public.products to authenticated;
grant select on public.quotes,public.quote_items to authenticated;
revoke all on public.clients,public.products,public.quotes,public.quote_items from anon;
create index on public.clients(user_id);
create index on public.products(user_id);
create index on public.quotes(user_id);
create index on public.quote_items(user_id,quote_id);
create function public.create_quote(p_client uuid,p_method text,p_percentage numeric,p_valid_until date,p_notes text,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid(); c public.clients; p public.products; q uuid; j jsonb; qty integer; price numeric; total_price numeric:=0;
begin
 if u is null then raise exception 'Acesso não autorizado'; end if;
 if p_method not in ('markup','margin') or p_method is null or p_percentage is null or p_percentage<0 or p_percentage>9999 or (p_method='margin' and p_percentage>=100) then raise exception 'Percentual inválido'; end if;
 if p_valid_until is null then raise exception 'Informe a validade'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Informe de 1 a 100 itens'; end if;
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
commit;
