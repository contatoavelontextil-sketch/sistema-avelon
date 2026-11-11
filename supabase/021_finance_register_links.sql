begin;
alter table public.fin_entries add column register_links jsonb not null default '{}'::jsonb;
create function public.save_fin_entry_v2(p_id uuid,p_kind text,p_class text,p_category text,p_description text,p_party text,p_amount numeric,p_due date,p_competence date,p_links jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;owner_id uuid:=public.workspace_owner();links jsonb:='{}';record_id uuid;record_name text;doc text;record_type text;product public.products;quantity numeric;unit_price numeric;begin
 perform public.require_permission('finance',case when p_id is null then 'create' else 'edit' end);
 if p_links is not null and jsonb_typeof(p_links)<>'object' then raise exception 'Vínculos de cadastro inválidos';end if;
 if p_links->'party' is not null then
  record_type:=p_links#>>'{party,type}';record_id:=(p_links#>>'{party,id}')::uuid;
  if record_type is distinct from (case when p_kind='income' then 'clients' else 'suppliers' end) then raise exception 'Entradas usam clientes; saídas usam fornecedores';end if;
  perform public.require_permission(record_type,'view');
  if record_type='clients' then select name,document into record_name,doc from public.clients where id=record_id and user_id=owner_id;
  else select name,document into record_name,doc from public.suppliers where id=record_id and user_id=owner_id and active;end if;
  if record_name is null then raise exception 'Cadastro não encontrado ou indisponível';end if;
  p_party:=record_name;links:=jsonb_build_object('party',jsonb_build_object('type',record_type,'id',record_id,'name',record_name,'document',doc));
 end if;
 if p_links->'product' is not null then
  perform public.require_permission('products','view');select * into product from public.products where id=(p_links#>>'{product,id}')::uuid and user_id=owner_id;
  if not found then raise exception 'Produto não encontrado';end if;
  quantity:=(p_links#>>'{product,quantity}')::numeric;unit_price:=(p_links#>>'{product,unit_price}')::numeric;
  if quantity is null or unit_price is null or quantity<=0 or quantity>1000000 or unit_price<0 or unit_price>9999999999 or quantity::text in ('NaN','Infinity','-Infinity') or unit_price::text in ('NaN','Infinity','-Infinity') then raise exception 'Quantidade ou preço do produto inválido';end if;
  links:=links||jsonb_build_object('product',jsonb_build_object('id',product.id,'name',product.name,'sku',product.sku,'quantity',quantity,'unit_price',unit_price));
 end if;
 result:=public.save_fin_entry(p_id,p_kind,p_class,p_category,p_description,p_party,p_amount,p_due,p_competence);
 update public.fin_entries set register_links=links where id=result;
 return result;
end $$;
revoke all on function public.save_fin_entry_v2(uuid,text,text,text,text,text,numeric,date,date,jsonb) from public;
grant execute on function public.save_fin_entry_v2(uuid,text,text,text,text,text,numeric,date,date,jsonb) to authenticated;
commit;
