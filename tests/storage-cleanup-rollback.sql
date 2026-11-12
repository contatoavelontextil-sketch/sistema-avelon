begin;

select set_config('request.jwt.claim.sub',public.workspace_owner()::text,true);
do $$ declare r jsonb;file_id uuid;parent uuid;denied boolean;begin
 select id into parent from public.quotes where user_id=public.workspace_owner() limit 1;
 r:=public.reserve_document_attachment('quote',parent,'TESTE ROLLBACK LIMPEZA.pdf','application/pdf',10);file_id:=(r->>'id')::uuid;
 denied:=false;begin perform public.owner_finish_attachment_delete(file_id);exception when others then denied:=true;end;if not denied then raise exception 'Finalizou sem preparação';end if;
 perform public.owner_prepare_attachment_delete(file_id);
 perform public.owner_finish_attachment_delete(file_id);
 perform public.owner_finish_attachment_delete(file_id);
 if not exists(select 1 from public.document_attachments where id=file_id and deleted_at is not null and archived) then raise exception 'Exclusão não registrada';end if;
 if (select count(*) from public.fin_audit where object_id=file_id and action='attachment_deleted')<>1 then raise exception 'Auditoria duplicada';end if;
 if public.owner_attachment_files() @> jsonb_build_array(jsonb_build_object('id',file_id)) then raise exception 'Excluído permanece disponível';end if;
 denied:=false;begin perform public.archive_document_attachment(file_id,false);exception when others then denied:=true;end;if not denied then raise exception 'Restaurou excluído';end if;
 denied:=false;begin perform public.finish_document_attachment(file_id);exception when others then denied:=true;end;if not denied then raise exception 'Concluiu upload excluído';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
 denied:=false;begin perform public.owner_attachment_files();exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Lista sem Mestre';end if;
 denied:=false;begin perform public.owner_prepare_attachment_delete(file_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Preparação sem Mestre';end if;
 denied:=false;begin perform public.owner_finish_attachment_delete(file_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'Conclusão sem Mestre';end if;
 if has_function_privilege('anon','public.owner_attachment_files()','execute') or has_function_privilege('anon','public.owner_prepare_attachment_delete(uuid)','execute') then raise exception 'Anônimo autorizado';end if;
end $$;
select 'PASSOU: gestão exclusiva, confirmação, auditoria idempotente e bloqueio de restauração; nenhum arquivo real removido.' as resultado;
rollback;
