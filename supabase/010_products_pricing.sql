begin;
alter table public.products add column reference text not null default '';
create table public.product_code_counters(user_id uuid primary key references auth.users(id),last_number bigint not null default 0);
alter table public.product_code_counters enable row level security;
revoke all on public.product_code_counters from public,anon,authenticated;
create index products_code_lookup on public.products(user_id,sku);
create function public.automatic_product_code() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare n bigint;code text;begin
 if tg_op='UPDATE' then new.sku:=old.sku;return new;end if;
 perform public.require_permission('products','create');
 if new.user_id is distinct from public.workspace_owner() then raise exception 'Empresa inválida';end if;
 if length(trim(coalesce(new.sku,'')))>0 and length(new.reference)=0 then new.reference:=new.sku;end if;
 loop
  insert into public.product_code_counters(user_id,last_number) values(new.user_id,1) on conflict(user_id) do update set last_number=product_code_counters.last_number+1 returning last_number into n;
  code:='AVL-'||lpad(n::text,greatest(6,length(n::text)),'0');
  exit when not exists(select 1 from public.products where user_id=new.user_id and sku=code);
 end loop;
 new.sku:=code;return new;
end $$;
revoke all on function public.automatic_product_code() from public;
create trigger products_automatic_code before insert or update on public.products for each row execute function public.automatic_product_code();
alter table public.quote_items add column suggested_price numeric(12,2),add column price_overridden boolean not null default false;
update public.quote_items set suggested_price=unit_price;
alter table public.quotes add column revision_of uuid,add foreign key(revision_of,user_id) references public.quotes(id,user_id);
create or replace function public.create_quote(p_client uuid,p_method text,p_percentage numeric,p_valid_until date,p_notes text,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=public.workspace_owner();c public.clients;p public.products;q uuid;j jsonb;qty integer;suggested numeric;price numeric;total_price numeric:=0;pricing jsonb;begin
 perform public.require_permission('quotes','create');perform public.require_permission('clients','view');perform public.require_permission('products','view');
 if p_method is null or p_method not in ('markup','margin') or p_percentage is null or p_percentage not between 0 and 9999 or (p_method='margin' and p_percentage>=100) then raise exception 'Percentual inválido';end if;
 select data into pricing from public.settings where user_id=u;pricing:=coalesce(pricing,'{}'::jsonb);
 if not public.can('quotes','price') and (p_method<>coalesce(pricing->>'method','markup') or p_percentage<>coalesce((pricing->>'percentage')::numeric,30)) then raise exception 'Seu acesso permite utilizar apenas o preço sugerido padrão';end if;
 if p_valid_until is null then raise exception 'Informe a validade';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Informe de 1 a 100 itens';end if;
 select * into c from public.clients where id=p_client and user_id=u;if not found then raise exception 'Cliente não encontrado';end if;
 insert into public.quotes(user_id,client_id,client_snapshot,method,percentage,notes,valid_until,total) values(u,c.id,jsonb_build_object('name',c.name,'kind',c.kind,'document',c.document,'phone',c.phone,'email',c.email,'address',c.address),p_method,p_percentage,coalesce(p_notes,''),p_valid_until,0) returning id into q;
 for j in select * from jsonb_array_elements(p_items) loop
  select * into p from public.products where id=(j->>'product_id')::uuid and user_id=u;if not found then raise exception 'Produto não encontrado';end if;
  qty:=(j->>'quantity')::integer;if qty is null or qty not between 1 and 100000 then raise exception 'Quantidade inválida';end if;
  suggested:=round(case when p_method='markup' then p.cost*(1+p_percentage/100) else p.cost/(1-p_percentage/100) end,2);
  price:=coalesce(nullif(j->>'custom_unit_price','')::numeric,suggested);
  if price not between 0 and 9999999999.99 then raise exception 'Preço unitário inválido';end if;price:=round(price,2);
  if price<>suggested and not public.can('quotes','price') then raise exception 'Sem permissão para alterar preços dos itens';end if;
  insert into public.quote_items(user_id,quote_id,product_id,description,quantity,cost_snapshot,unit_price,suggested_price,price_overridden,details) values(u,q,p.id,p.name,qty,p.cost,price,suggested,price<>suggested,coalesce(j->>'details',''));
  total_price:=total_price+price*qty;
 end loop;
 update public.quotes set total=total_price where id=q;return q;
end $$;
create function public.create_quote_v3(p_client uuid,p_method text,p_percentage numeric,p_valid_until date,p_notes text,p_items jsonb,p_meta jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare q uuid;parent uuid:=nullif(p_meta->>'revision_of','')::uuid;begin
 if parent is not null then perform public.require_permission('quotes','view');if not exists(select 1 from public.quotes where id=parent and user_id=public.workspace_owner()) then raise exception 'Proposta de origem indisponível';end if;end if;
 q:=public.create_quote_v2(p_client,p_method,p_percentage,p_valid_until,p_notes,p_items,p_meta);
 update public.quotes set revision_of=parent where id=q;return q;
end $$;
revoke all on function public.create_quote_v3(uuid,text,numeric,date,text,jsonb,jsonb) from public;
grant execute on function public.create_quote_v3(uuid,text,numeric,date,text,jsonb,jsonb) to authenticated;
commit;
