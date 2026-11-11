begin;
create table public.document_attachments(id uuid primary key default gen_random_uuid(),user_id uuid not null default public.workspace_owner(),parent_type text not null check(parent_type in ('quote','entry','receipt')),parent_id uuid not null,storage_path text not null unique,original_name text not null check(length(original_name) between 1 and 200),mime_type text not null check(mime_type in ('application/pdf','image/png','image/jpeg','image/webp')),byte_size bigint not null check(byte_size between 1 and 10485760),state text not null default 'uploading' check(state in ('uploading','ready')),archived boolean not null default false,created_by uuid not null default auth.uid(),created_at timestamptz not null default now());
create function public.attachment_access(p_type text,p_parent uuid,p_action text) returns boolean language plpgsql stable security definer set search_path=public,pg_temp as $$declare module text;exists_parent boolean;module_write boolean;begin
 if p_action is null or p_action not in ('view','create','edit') or not public.can('attachments',p_action) then return false;end if;
 if p_type='quote' then module:='quotes';select exists(select 1 from public.quotes where id=p_parent and user_id=public.workspace_owner()) into exists_parent;module_write:=public.can('quotes','create') or public.can('workflow','edit');
 elsif p_type='entry' then module:='finance';select exists(select 1 from public.fin_entries where id=p_parent and user_id=public.workspace_owner()) into exists_parent;module_write:=public.can('finance','create') or public.can('finance','edit');
 elsif p_type='receipt' then module:='receipts';select exists(select 1 from public.payment_receipts where id=p_parent and user_id=public.workspace_owner()) into exists_parent;module_write:=public.can('receipts','create');
 else return false;end if;
 return exists_parent and (public.can(module,'view') or (p_type='quote' and public.can('workflow','view'))) and (p_action='view' or module_write);
end $$;
alter table public.document_attachments enable row level security;
revoke all on public.document_attachments from public,anon,authenticated;grant select on public.document_attachments to authenticated;
create policy document_attachments_read on public.document_attachments for select to authenticated using(user_id=public.workspace_owner() and public.attachment_access(parent_type,parent_id,'view'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('avelon-private-documents','avelon-private-documents',false,10485760,array['application/pdf','image/png','image/jpeg','image/webp']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy avelon_private_documents_read on storage.objects for select to authenticated using(bucket_id='avelon-private-documents' and exists(select 1 from public.document_attachments a where a.storage_path=name and a.user_id=public.workspace_owner() and public.attachment_access(a.parent_type,a.parent_id,'view')));
create policy avelon_private_documents_insert on storage.objects for insert to authenticated with check(bucket_id='avelon-private-documents' and exists(select 1 from public.document_attachments a where a.storage_path=name and a.user_id=public.workspace_owner() and a.created_by=auth.uid() and a.state='uploading' and public.attachment_access(a.parent_type,a.parent_id,'create')));
create function public.reserve_document_attachment(p_type text,p_parent uuid,p_name text,p_mime text,p_bytes bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$declare new_id uuid:=gen_random_uuid();path text;extension text;begin
 if not public.attachment_access(p_type,p_parent,'create') then raise exception 'Seu acesso não permite anexar documentos a este registro';end if;
 if p_name is null or length(p_name) not between 1 and 200 or p_bytes is null or p_bytes not between 1 and 10485760 or p_mime is null or p_mime not in ('application/pdf','image/png','image/jpeg','image/webp') then raise exception 'Escolha PDF, PNG, JPG ou WebP de até 10 MB';end if;
 extension:=case p_mime when 'application/pdf' then '.pdf' when 'image/png' then '.png' when 'image/jpeg' then '.jpg' else '.webp' end;
 path:=public.workspace_owner()::text||'/'||new_id::text||extension;
 insert into public.document_attachments(id,parent_type,parent_id,storage_path,original_name,mime_type,byte_size) values(new_id,p_type,p_parent,path,regexp_replace(p_name,'[[:cntrl:]]','','g'),p_mime,p_bytes);
 return jsonb_build_object('id',new_id,'storage_path',path);
end $$;
create function public.finish_document_attachment(p_attachment uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$declare a public.document_attachments;size_text text;begin
 select * into a from public.document_attachments where id=p_attachment and user_id=public.workspace_owner() for update;
 if not found or a.created_by<>auth.uid() or not public.attachment_access(a.parent_type,a.parent_id,'create') then raise exception 'Anexo não autorizado';end if;
 if a.state='ready' then return;end if;
 select metadata->>'size' into size_text from storage.objects where bucket_id='avelon-private-documents' and name=a.storage_path;
 if not found then raise exception 'O arquivo ainda não terminou de enviar. Tente novamente';end if;
 if size_text is not null and size_text::bigint<>a.byte_size then raise exception 'O tamanho recebido não confere com o arquivo informado';end if;
 update public.document_attachments set state='ready' where id=a.id;
 insert into public.fin_audit(object_id,action,detail) values(a.id,'attachment_added',jsonb_build_object('parent_type',a.parent_type,'parent_id',a.parent_id,'name',a.original_name));
end $$;
create function public.archive_document_attachment(p_attachment uuid,p_archived boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$declare a public.document_attachments;begin
 select * into a from public.document_attachments where id=p_attachment and user_id=public.workspace_owner() for update;
 if not found or p_archived is null or not public.attachment_access(a.parent_type,a.parent_id,'edit') then raise exception 'Seu acesso não permite arquivar este anexo';end if;
 update public.document_attachments set archived=p_archived where id=a.id;
 insert into public.fin_audit(object_id,action,detail) values(a.id,case when p_archived then 'attachment_archived' else 'attachment_restored' end,jsonb_build_object('parent_type',a.parent_type,'parent_id',a.parent_id));
end $$;
revoke all on function public.attachment_access(text,uuid,text),public.reserve_document_attachment(text,uuid,text,text,bigint),public.finish_document_attachment(uuid),public.archive_document_attachment(uuid,boolean) from public;
grant execute on function public.attachment_access(text,uuid,text),public.reserve_document_attachment(text,uuid,text,text,bigint),public.finish_document_attachment(uuid),public.archive_document_attachment(uuid,boolean) to authenticated;
commit;
