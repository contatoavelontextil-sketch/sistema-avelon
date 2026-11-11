begin;
create function public.normalize_register_document(p_value text) returns text language sql immutable set search_path=public,pg_temp as $$select regexp_replace(upper(coalesce(p_value,'')),'[^0-9A-Z]','','g')$$;
create function public.normalize_register_name(p_value text) returns text language sql immutable set search_path=public,pg_temp as $$select lower(regexp_replace(trim(translate(coalesce(p_value,''),'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ','aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),'\s+',' ','g'))$$;
create table public.suppliers(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner() references auth.users(id),kind text not null check(kind in ('PF','PJ')),name text not null check(length(trim(name)) between 2 and 200),document text not null default '' check(length(document)<=20),phone text not null default '' check(length(phone)<=25),email text not null default '' check(length(email)<=200),address text not null default '' check(length(address)<=500),active boolean not null default true,created_at timestamptz not null default now(),unique(id,user_id));
alter table public.suppliers enable row level security;
revoke all on public.suppliers from public,anon,authenticated;
grant select,insert,update on public.suppliers to authenticated;
create policy suppliers_read on public.suppliers for select to authenticated using(user_id=public.workspace_owner() and public.can('suppliers','view'));
create policy suppliers_create on public.suppliers for insert to authenticated with check(user_id=public.workspace_owner() and public.can('suppliers','create'));
create policy suppliers_edit on public.suppliers for update to authenticated using(user_id=public.workspace_owner() and public.can('suppliers','edit')) with check(user_id=public.workspace_owner() and public.can('suppliers','edit'));
create unique index supplier_document_unique on public.suppliers(user_id,public.normalize_register_document(document)) where length(public.normalize_register_document(document)) in (11,14);
create table public.register_import_batches(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),record_type text not null check(record_type in ('clients','suppliers','products')),source_name text not null,source_uri text not null,source_sheet text not null,created_by uuid not null default auth.uid(),created_at timestamptz not null default now(),inserted integer not null default 0,updated integer not null default 0,skipped integer not null default 0);
create table public.register_import_rows(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),source_uri text not null,source_sheet text not null,source_row integer not null,record_type text not null,record_id uuid not null,source_hash text not null,batch_id uuid not null references public.register_import_batches(id),unique(user_id,source_uri,source_sheet,source_row,record_type));
alter table public.register_import_batches enable row level security;alter table public.register_import_rows enable row level security;
revoke all on public.register_import_batches,public.register_import_rows from public,anon,authenticated;
grant select on public.register_import_batches,public.register_import_rows to authenticated;
create policy register_batches_read on public.register_import_batches for select to authenticated using(user_id=public.workspace_owner() and exists(select 1 from public.profiles where id=auth.uid() and active and is_owner));
create policy register_rows_read on public.register_import_rows for select to authenticated using(user_id=public.workspace_owner() and exists(select 1 from public.profiles where id=auth.uid() and active and is_owner));
create function public.import_register_batch(p_type text,p_source jsonb,p_rows jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare owner_id uuid:=public.workspace_owner();batch uuid;j jsonb;rec uuid;doc text;nm text;prior public.register_import_rows;inserted_count integer:=0;updated_count integer:=0;skipped_count integer:=0;uri text:=coalesce(p_source->>'uri','');sheet_name text:=coalesce(p_source->>'sheet','');source_name text:=coalesce(p_source->>'name','');c public.clients;s public.suppliers;pr public.products;begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_owner) then raise exception 'Importação exclusiva do Mestre Criador';end if;
 if p_type is null or p_type not in ('clients','suppliers','products') or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>1000 or length(uri) not between 1 and 1000 or length(sheet_name)>200 or length(source_name)>200 then raise exception 'Fonte ou registros inválidos';end if;
 perform public.require_permission(p_type,'create');perform pg_advisory_xact_lock(hashtext(owner_id::text||':register-import'));
 insert into public.register_import_batches(record_type,source_name,source_uri,source_sheet) values(p_type,source_name,uri,sheet_name) returning id into batch;
 for j in select value from jsonb_array_elements(p_rows) loop
  nm:=trim(coalesce(j->>'name',''));doc:=public.normalize_register_document(j->>'document');rec:=null;
  if length(nm) not between 2 and 200 or coalesce((j->>'source_row')::integer,0)<1 then raise exception 'Nome ou linha inválida na fonte';end if;
  select * into prior from public.register_import_rows where user_id=owner_id and source_uri=uri and source_sheet=sheet_name and source_row=(j->>'source_row')::integer and record_type=p_type;
  if found and prior.source_hash=md5(j::text) then skipped_count:=skipped_count+1;continue;end if;
  if p_type='products' then
   select * into pr from public.products where user_id=owner_id and public.normalize_register_name(name)=public.normalize_register_name(nm) order by created_at limit 1;
   if found then rec:=pr.id;skipped_count:=skipped_count+1;
   else insert into public.products(name,reference,cost,retail,wholesale) values(nm,coalesce(j->>'reference',''),(j->>'cost')::numeric,coalesce((j->>'retail')::numeric,0),coalesce((j->>'wholesale')::numeric,0)) returning id into rec;inserted_count:=inserted_count+1;end if;
  elsif p_type='clients' then
   select * into c from public.clients where user_id=owner_id and ((doc<>'' and public.normalize_register_document(document)=doc) or (public.normalize_register_name(name)=public.normalize_register_name(nm) and (doc='' or public.normalize_register_document(document) in ('','000','00000000000','00000000000000') or public.normalize_register_document(document)=doc))) order by (doc<>'' and public.normalize_register_document(document)=doc) desc,created_at limit 1;
   if found then rec:=c.id;
    if (c.document in ('','000','00000000000','00000000000000') and doc<>'') or (c.phone='' and coalesce(j->>'phone','')<>'') or (c.email='' and coalesce(j->>'email','')<>'') or (c.address in ('','XXX','xxx','****') and coalesce(j->>'address','')<>'') then
     update public.clients set document=case when document in ('','000','00000000000','00000000000000') and doc<>'' then doc else document end,phone=case when phone='' then coalesce(j->>'phone','') else phone end,email=case when email='' then coalesce(j->>'email','') else email end,address=case when address in ('','XXX','xxx','****') then coalesce(j->>'address','') else address end where id=rec;updated_count:=updated_count+1;
    else skipped_count:=skipped_count+1;end if;
   else insert into public.clients(kind,name,document,phone,email,address) values(coalesce(j->>'kind','PF'),nm,doc,coalesce(j->>'phone',''),coalesce(j->>'email',''),coalesce(j->>'address','')) returning id into rec;inserted_count:=inserted_count+1;end if;
  else
   select * into s from public.suppliers where user_id=owner_id and ((doc<>'' and public.normalize_register_document(document)=doc) or (public.normalize_register_name(name)=public.normalize_register_name(nm) and (doc='' or public.normalize_register_document(document) in ('',doc)))) order by created_at limit 1;
   if found then rec:=s.id;skipped_count:=skipped_count+1;
   else insert into public.suppliers(kind,name,document,phone,email,address) values(coalesce(j->>'kind','PJ'),nm,doc,coalesce(j->>'phone',''),coalesce(j->>'email',''),coalesce(j->>'address','')) returning id into rec;inserted_count:=inserted_count+1;end if;
  end if;
  insert into public.register_import_rows(source_uri,source_sheet,source_row,record_type,record_id,source_hash,batch_id) values(uri,sheet_name,(j->>'source_row')::integer,p_type,rec,md5(j::text),batch) on conflict(user_id,source_uri,source_sheet,source_row,record_type) do update set record_id=excluded.record_id,source_hash=excluded.source_hash,batch_id=excluded.batch_id;
 end loop;
 update public.register_import_batches set inserted=inserted_count,updated=updated_count,skipped=skipped_count where id=batch;
 return jsonb_build_object('id',batch,'inserted',inserted_count,'updated',updated_count,'skipped',skipped_count);
end $$;
revoke all on function public.import_register_batch(text,jsonb,jsonb) from public;
grant execute on function public.import_register_batch(text,jsonb,jsonb) to authenticated;
commit;
