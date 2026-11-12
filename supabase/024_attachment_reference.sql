begin;
create or replace function public.owner_attachment_files() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_owner) then raise exception 'Área exclusiva do Mestre Criador' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'storage_path',a.storage_path,'name',a.original_name,'byte_size',a.byte_size,'created_at',a.created_at,'archived',a.archived,'state',a.state,'parent_type',a.parent_type,'parent_id',a.parent_id,'purge_pending',a.purge_requested_at is not null,'file_present',exists(select 1 from storage.objects o where o.bucket_id='avelon-private-documents' and o.name=a.storage_path),'reference',case a.parent_type when 'quote' then (select '#'||lpad(coalesce(q.base_number,q.number)::text,greatest(4,length(coalesce(q.base_number,q.number)::text)),'0')||case when coalesce(q.revision_no,0)>0 then ' Rev. '||lpad(q.revision_no::text,greatest(2,length(q.revision_no::text)),'0') else '' end from public.quotes q where q.id=a.parent_id) when 'entry' then (select e.description from public.fin_entries e where e.id=a.parent_id) when 'receipt' then 'Recibo' end) order by a.created_at), '[]'::jsonb) from public.document_attachments a where a.user_id=public.workspace_owner() and a.deleted_at is null);
end $$;
commit;

