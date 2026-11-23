begin;
update public.settings set data=jsonb_set(jsonb_set(data,'{production,require_art}','true'::jsonb),'{production,require_deposit}','true'::jsonb) where user_id=public.workspace_owner();
set local role authenticated;
select set_config('request.jwt.claim.sub',public.workspace_owner()::text,true);
do $$
declare c uuid;p uuid;q uuid;a uuid;r jsonb;again jsonb;stamp timestamptz;req uuid:=gen_random_uuid();count_before bigint;denied boolean;receipt uuid;
begin
 insert into public.clients(kind,name) values('PF','TESTE FLUXO SIMPLIFICADO - ROLLBACK') returning id into c;
 insert into public.products(name,cost,retail,wholesale) values('TESTE FLUXO SIMPLIFICADO',10,20,20) returning id into p;
 q:=public.create_quote_v3(c,'markup',100,current_date,'TESTE ROLLBACK',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5)),'{"entry_percentage":50,"technique":"Silk"}');
 a:=public.save_account(null,'TESTE FLUXO SIMPLIFICADO',0,current_date,true);
 select updated_at into stamp from public.quotes where id=q;
 -- A failed stage (art not approved) must roll back receivables and cash as well.
 denied:=false;
 begin perform public.advance_order_with_payment(q,'production',current_date,'{"art_approved":false}','',stamp,true,50,a,current_date,'Pix','TESTE',req);exception when others then denied:=true;end;
 if not denied or exists(select 1 from public.fin_entries where quote_id=q) then raise exception 'Falha de produção deixou lançamento parcial';end if;
 r:=public.advance_order_with_payment(q,'production',current_date,'{"art_approved":true}','',stamp,true,50,a,current_date,'Pix','TESTE',req);
 if r->>'receipt' is null or (r->>'recorded')::numeric<>50 then raise exception 'Entrada sem recibo';end if;
 if (select count(*) from public.fin_entries where quote_id=q)<>2 then raise exception 'Parcelas incorretas';end if;
 select count(*) into count_before from public.fin_settlements;
 again:=public.advance_order_with_payment(q,'production',current_date,'{"art_approved":true}','',stamp,true,50,a,current_date,'Pix','TESTE',req);
 if r<>again or count_before<>(select count(*) from public.fin_settlements) then raise exception 'Repetição duplicou caixa';end if;
 denied:=false;
 begin perform public.advance_order_with_payment(q,'production',current_date,'{"art_approved":true}','',stamp,true,40,a,current_date,'Pix','TESTE',req);exception when others then denied:=true;end;
 if not denied then raise exception 'Pedido repetido aceitou conteúdo diferente';end if;
 select updated_at into stamp from public.quotes where id=q;
 -- The previous interface cannot register the deposit a second time as delivery balance.
 denied:=false;
 begin perform public.start_order_with_receipt(q,'cutting',current_date,'{"art_approved":true}','',stamp,50,true,false,a,current_date,'Pix','',gen_random_uuid());exception when others then denied:=true;end;
 if not denied or count_before<>(select count(*) from public.fin_settlements) then raise exception 'Interface antiga duplicou a entrada no saldo';end if;
 -- No means no settlement. Fully paid production entry already has a receipt to reuse.
 again:=public.advance_order_with_payment(q,'cutting',current_date,'{"art_approved":true}','',stamp,false,0,null,null,'','',gen_random_uuid());
 if count_before<>(select count(*) from public.fin_settlements) or again->>'receipt'<>r->>'receipt' then raise exception 'Troca de departamento duplicou recebimento/recibo';end if;
 select updated_at into stamp from public.quotes where id=q;
 denied:=false;
 begin perform public.advance_order_with_payment(q,'completed',current_date,'{"art_approved":true}','',stamp,true,25,a,current_date,'Pix','',gen_random_uuid());exception when others then denied:=true;end;
 if not denied or count_before<>(select count(*) from public.fin_settlements) or (select stage from public.quotes where id=q)<>'cutting' then raise exception 'Finalização parcial não foi revertida';end if;
 req:=gen_random_uuid();
 r:=public.advance_order_with_payment(q,'completed',current_date,'{"art_approved":true}','',stamp,true,50,a,current_date,'Pix','',req);
 receipt:=(r->>'receipt')::uuid;
 if (select stage from public.quotes where id=q)<>'completed' or (select kind from public.payment_receipts where id=receipt)<>'final' then raise exception 'Finalização sem recibo final';end if;
 if (select sum(s.amount) from public.fin_settlements s join public.fin_entries e on e.id=s.entry_id where e.quote_id=q and not s.reversed)<>100 then raise exception 'Quitação incorreta';end if;
 if jsonb_array_length(public.receipt_view_data(receipt)->'receipt'->'snapshot'->'payments')<>2 then raise exception 'Histórico financeiro incompleto';end if;
 if not exists(select 1 from public.quote_events where quote_id=q and next_stage='completed' and note like 'Finalização direta%') then raise exception 'Salto não identificado';end if;
 denied:=false;
 begin perform public.advance_order_with_payment(q,'completed',current_date,'{"art_approved":true}','',stamp,false,0,null,null,'','',gen_random_uuid());exception when others then denied:=true;end;
 -- Permission isolation: an authenticated profile with no workflow permission cannot use the RPC.
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 denied:=false;
 begin perform public.advance_order_with_payment(q,'completed',current_date,'{}','',stamp,false,0,null,null,'','',gen_random_uuid());exception when others then denied:=true;end;
 if not denied then raise exception 'Sem permissão conseguiu confirmar';end if;
end $$;
reset role;
select 'PASSOU: entrada, parcelas, recibo, repetição, não recebido, rollback integral, conclusão direta e permissões' as resultado;
rollback;
