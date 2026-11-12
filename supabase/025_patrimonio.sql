begin;
alter table public.company_assets alter column acquired_on drop not null,
 add column asset_number bigint unique check(asset_number>0),
 add column specifications text not null default '' check(length(specifications)<=3000),
 add column acquisition_month_only boolean not null default false,
 add column label_token uuid unique,
 add column archived boolean not null default false;
create sequence public.company_asset_number;
alter sequence public.company_asset_number owned by public.company_assets.asset_number;
alter table public.company_assets alter column asset_number set default nextval('public.company_asset_number');
revoke all on sequence public.company_asset_number from public,anon,authenticated;

create or replace function public.save_company_asset(p_id uuid,p_data jsonb) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;
begin
 perform public.require_permission('assets',case when p_id is null then 'create' else 'edit' end);
 if length(btrim(coalesce(p_data->>'name',''))) not between 1 and 200 then raise exception 'Informe o nome do bem';end if;
 if p_id is null then
  insert into public.company_assets(name,acquired_on,cost,residual,life_months,notes,active,specifications,acquisition_month_only)
  values(btrim(p_data->>'name'),nullif(p_data->>'acquired_on','')::date,(p_data->>'cost')::numeric,coalesce((p_data->>'residual')::numeric,0),coalesce((p_data->>'life_months')::integer,120),coalesce(p_data->>'notes',''),coalesce((p_data->>'active')::boolean,true),coalesce(p_data->>'specifications',''),coalesce((p_data->>'acquisition_month_only')::boolean,false)) returning id into result;
 else
  update public.company_assets set name=btrim(p_data->>'name'),notes=coalesce(p_data->>'notes',notes),
   acquired_on=case when p_data?'acquired_on' then nullif(p_data->>'acquired_on','')::date else acquired_on end,
   acquisition_month_only=coalesce((p_data->>'acquisition_month_only')::boolean,acquisition_month_only),
   specifications=coalesce(p_data->>'specifications',specifications),
   active=coalesce((p_data->>'active')::boolean,active),
   asset_number=coalesce(asset_number,nextval('public.company_asset_number'))
  where id=p_id and user_id=public.workspace_owner() and not archived returning id into result;
 end if;
 if result is null then raise exception 'Bem não encontrado';end if;
 return result;
end $$;

create function public.set_company_asset_label(p_id uuid,p_enabled boolean) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;
begin
 perform public.require_permission('assets','edit');
 update public.company_assets set label_token=case when p_enabled then coalesce(label_token,gen_random_uuid()) else null end,
   asset_number=coalesce(asset_number,nextval('public.company_asset_number'))
 where id=p_id and user_id=public.workspace_owner() and active and not archived returning label_token into result;
 if not found then raise exception 'Bem ativo não encontrado';end if;
 return result;
end $$;
create function public.company_asset_card(p_token uuid) returns jsonb
language sql stable security definer set search_path=public,pg_temp as $$
 select jsonb_build_object('number',a.asset_number,'name',a.name,'specifications',a.specifications,
 'company',coalesce(nullif(s.data->>'company',''),'Avelon Têxtil'),
 'contact','Instagram: @avelon_textil · WhatsApp: (38) 9 8816-9968')
 from public.company_assets a left join public.settings s on s.user_id=a.user_id
 where a.label_token=p_token and a.active and not a.archived;
$$;
revoke all on function public.set_company_asset_label(uuid,boolean),public.company_asset_card(uuid) from public;
grant execute on function public.set_company_asset_label(uuid,boolean) to authenticated;
grant execute on function public.company_asset_card(uuid) to anon,authenticated;

alter table public.document_attachments drop constraint document_attachments_parent_type_check;
alter table public.document_attachments add constraint document_attachments_parent_type_check check(parent_type in ('quote','entry','receipt','asset'));
create or replace function public.attachment_access(p_type text,p_parent uuid,p_action text) returns boolean language plpgsql stable security definer set search_path=public,pg_temp as $$declare module text;exists_parent boolean;module_write boolean;begin
 if p_action is null or p_action not in ('view','create','edit') or not public.can('attachments',p_action) then return false;end if;
 if p_type='quote' then module:='quotes';select exists(select 1 from public.quotes where id=p_parent and user_id=public.workspace_owner()) into exists_parent;module_write:=public.can('quotes','create') or public.can('workflow','edit');
 elsif p_type='entry' then module:='finance';select exists(select 1 from public.fin_entries where id=p_parent and user_id=public.workspace_owner()) into exists_parent;module_write:=public.can('finance','create') or public.can('finance','edit');
 elsif p_type='receipt' then module:='receipts';select exists(select 1 from public.payment_receipts where id=p_parent and user_id=public.workspace_owner()) into exists_parent;module_write:=public.can('receipts','create');
 elsif p_type='asset' then module:='assets';select exists(select 1 from public.company_assets where id=p_parent and user_id=public.workspace_owner() and not archived) into exists_parent;module_write:=public.can('assets','edit');
 else return false;end if;
 return exists_parent and (public.can(module,'view') or (p_type='quote' and public.can('workflow','view'))) and (p_action='view' or module_write);
end $$;
commit;
