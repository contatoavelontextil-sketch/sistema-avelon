begin;
alter table public.document_attachments add column deleted_at timestamptz,add column deleted_by uuid,add column purge_requested_at timestamptz;
create function public.owner_attachment_files() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_owner) then raise exception 'Área exclusiva do Mestre Criador' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'storage_path',a.storage_path,'name',a.original_name,'byte_size',a.byte_size,'created_at',a.created_at,'archived',a.archived,'state',a.state,'parent_type',a.parent_type,'parent_id',a.parent_id,'purge_pending',a.purge_requested_at is not null,'file_present',exists(select 1 from storage.objects o where o.bucket_id='avelon-private-documents' and o.name=a.storage_path),'reference',case a.parent_type when 'quote' then (select '#'||q.number::text from public.quotes q where q.id=a.parent_id) when 'entry' then (select e.description from public.fin_entries e where e.id=a.parent_id) when 'receipt' then 'Recibo' end) order by a.created_at), '[]'::jsonb) from public.document_attachments a where a.user_id=public.workspace_owner() and a.deleted_at is null);
end $$;
create function public.owner_prepare_attachment_delete(p_attachment uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.document_attachments;begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_owner) then raise exception 'Área exclusiva do Mestre Criador' using errcode='42501';end if;
 select * into a from public.document_attachments where id=p_attachment and user_id=public.workspace_owner() for update;
 if not found then raise exception 'Anexo não encontrado';end if;
 if a.deleted_at is not null then return jsonb_build_object('id',a.id,'already_deleted',true);end if;
 update public.document_attachments set archived=true,purge_requested_at=clock_timestamp() where id=a.id;
 insert into public.fin_audit(object_id,action,detail) values(a.id,'attachment_delete_requested',jsonb_build_object('name',a.original_name,'bytes',a.byte_size,'parent_type',a.parent_type,'parent_id',a.parent_id));
 return jsonb_build_object('id',a.id,'storage_path',a.storage_path,'name',a.original_name,'already_deleted',false);
end $$;
create function public.owner_finish_attachment_delete(p_attachment uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare a public.document_attachments;begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_owner) then raise exception 'Área exclusiva do Mestre Criador' using errcode='42501';end if;
 select * into a from public.document_attachments where id=p_attachment and user_id=public.workspace_owner() for update;
 if not found then raise exception 'Anexo não encontrado';end if;
 if a.deleted_at is not null then return;end if;
 if a.purge_requested_at is null then raise exception 'Confirme a exclusão antes de concluir';end if;
 if exists(select 1 from storage.objects where bucket_id='avelon-private-documents' and name=a.storage_path) then raise exception 'O arquivo ainda está armazenado. A exclusão não foi concluída';end if;
 update public.document_attachments set deleted_at=clock_timestamp(),deleted_by=auth.uid(),archived=true where id=a.id;
 insert into public.fin_audit(object_id,action,detail) values(a.id,'attachment_deleted',jsonb_build_object('name',a.original_name,'bytes',a.byte_size,'parent_type',a.parent_type,'parent_id',a.parent_id,'kept_order_and_finance',true));
end $$;
-- O arquivo real é removido pela API Storage, nunca por DELETE SQL de metadados.
create policy avelon_private_documents_owner_delete on storage.objects for delete to authenticated using(
 bucket_id='avelon-private-documents' and exists(select 1 from public.profiles p where p.id=auth.uid() and p.active and p.is_owner)
 and exists(select 1 from public.document_attachments a where a.storage_path=name and a.user_id=public.workspace_owner() and a.deleted_at is null and a.purge_requested_at>now()-interval '15 minutes'));
create or replace function public.finish_document_attachment(p_attachment uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$declare a public.document_attachments;size_text text;begin
 select * into a from public.document_attachments where id=p_attachment and user_id=public.workspace_owner() for update;
 if not found or a.created_by<>auth.uid() or not public.attachment_access(a.parent_type,a.parent_id,'create') then raise exception 'Anexo não autorizado';end if;
 if a.deleted_at is not null or a.purge_requested_at is not null then raise exception 'Anexo excluído ou com exclusão em andamento';end if;
 if a.state='ready' then return;end if;
 select metadata->>'size' into size_text from storage.objects where bucket_id='avelon-private-documents' and name=a.storage_path;
 if not found then raise exception 'O arquivo ainda não terminou de enviar. Tente novamente';end if;
 if size_text is not null and size_text::bigint<>a.byte_size then raise exception 'O tamanho recebido não confere com o arquivo informado';end if;
 update public.document_attachments set state='ready' where id=a.id;
 insert into public.fin_audit(object_id,action,detail) values(a.id,'attachment_added',jsonb_build_object('parent_type',a.parent_type,'parent_id',a.parent_id,'name',a.original_name));
end $$;

-- Bloqueia novo upload no caminho de um anexo já excluído ou em exclusão.
create policy avelon_private_documents_insert_cleanup_guard on storage.objects as restrictive for insert to authenticated with check(
 bucket_id<>'avelon-private-documents' or exists(select 1 from public.document_attachments a where a.storage_path=name and a.deleted_at is null and a.purge_requested_at is null));
create or replace function public.archive_document_attachment(p_attachment uuid,p_archived boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$declare a public.document_attachments;begin
 select * into a from public.document_attachments where id=p_attachment and user_id=public.workspace_owner() for update;
 if not found or p_archived is null or not public.attachment_access(a.parent_type,a.parent_id,'edit') then raise exception 'Seu acesso não permite arquivar este anexo';end if;
 if a.deleted_at is not null or a.purge_requested_at is not null then raise exception 'Anexo excluído ou com exclusão em andamento. Consulte Uso e armazenamento';end if;
 update public.document_attachments set archived=p_archived where id=a.id;
 insert into public.fin_audit(object_id,action,detail) values(a.id,case when p_archived then 'attachment_archived' else 'attachment_restored' end,jsonb_build_object('parent_type',a.parent_type,'parent_id',a.parent_id));
end $$;
revoke all on function public.owner_attachment_files(),public.owner_prepare_attachment_delete(uuid),public.owner_finish_attachment_delete(uuid) from public,anon;
grant execute on function public.owner_attachment_files(),public.owner_prepare_attachment_delete(uuid),public.owner_finish_attachment_delete(uuid) to authenticated;
commit;
