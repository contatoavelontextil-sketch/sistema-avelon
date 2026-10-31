begin;
create or replace function public.create_quote(p_client uuid,p_method text,p_percentage numeric,p_valid_until date,p_notes text,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=public.workspace_owner(); c public.clients; p public.products; q uuid; j jsonb; qty integer; price numeric; total_price numeric:=0;
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