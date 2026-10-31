-- Run in the Avelon project SQL editor. All fixture data and setting changes roll back.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',public.workspace_owner()::text,true);
do $$
declare a uuid;e uuid;s uuid;line uuid;q uuid;result jsonb;n integer;denied boolean;meta jsonb:='{"art_approved":true,"technique":"Silk"}';
begin
 a:=public.save_account(null,'TESTE TRANSACIONAL',100,'2026-10-01',true);
 e:=public.save_fin_entry(null,'income','revenue','Vendas','TESTE TRANSACIONAL','',100,'2026-10-31','2026-10-01');
 s:=public.settle_entry(e,a,40,'2026-10-31','TESTE',gen_random_uuid());
 if (select sum(amount) from public.fin_settlements where entry_id=e and not reversed)<>40 then raise exception 'Falha na baixa parcial';end if;
 denied:=false;begin perform public.settle_entry(e,a,61,'2026-10-31','TESTE',gen_random_uuid());exception when others then denied:=true;end;if not denied then raise exception 'Permitida baixa maior que saldo';end if;
 result:=public.import_bank_lines(a,'teste.csv','fixture','[{"date":"2026-10-31","description":"TESTE","amount":40,"external_id":"fixture:1"}]');
 if (result->>'imported')::integer<>1 then raise exception 'Importação falhou';end if;
 result:=public.import_bank_lines(a,'teste.csv','fixture','[{"date":"2026-10-31","description":"TESTE","amount":40,"external_id":"fixture:1"}]');
 if (result->>'duplicates')::integer<>1 then raise exception 'Duplicata não detectada';end if;
 select id into line from public.bank_lines where account_id=a and external_id='fixture:1';
 perform public.reconcile_bank_line(line,null,s,null,gen_random_uuid());
 if (select count(*) from public.fin_settlements where entry_id=e)<>1 then raise exception 'Conciliação duplicou caixa';end if;
 perform public.reverse_settlement(s,'TESTE estorno');
 if (select status from public.bank_lines where id=line)<>'pending' then raise exception 'Estorno não liberou extrato';end if;
 perform public.reconcile_bank_line(line,e,null,null,gen_random_uuid());
 if (select sum(amount) from public.fin_settlements where entry_id=e and not reversed)<>40 then raise exception 'Reconciliar após estorno falhou';end if;
 select id into q from public.quotes order by number limit 1;
 if q is not null then
  n:=public.prepare_receivables(q,'2026-10-31','2026-11-30');
  n:=public.prepare_receivables(q,'2026-10-31','2026-11-30');if n<>0 then raise exception 'Parcelas duplicadas';end if;
  denied:=false;begin perform public.update_order(q,'production',null,meta,'TESTE',null);exception when others then denied:=true;end;if not denied then raise exception 'Produção sem entrada permitida';end if;
  select id into e from public.fin_entries where quote_id=q and installment=1;
  perform public.settle_entry(e,a,(select amount from public.fin_entries where id=e),'2026-10-31','TESTE',gen_random_uuid());
  denied:=false;begin perform public.update_order(q,'production',null,'{"art_approved":false}','TESTE',null);exception when others then denied:=true;end;if not denied then raise exception 'Produção sem aprovação da arte permitida';end if;
  perform public.update_order(q,'production',null,meta,'TESTE',null);
  denied:=false;begin perform public.update_order(q,'completed',null,meta,'TESTE',null);exception when others then denied:=true;end;if not denied then raise exception 'Finalização sem saldo permitida';end if;
  select id into e from public.fin_entries where quote_id=q and installment=2;
  perform public.settle_entry(e,a,(select amount from public.fin_entries where id=e),'2026-10-31','TESTE',gen_random_uuid());
  perform public.update_order(q,'completed',null,meta,'TESTE',null);
 end if;
 perform public.save_settings('{"accent":"#b89b68"}');
 denied:=false;begin perform public.save_settings('{"accent":"invalid"}');exception when others then denied:=true;end;if not denied then raise exception 'Cor inválida permitida';end if;
end $$;
reset role;
select 'PASSOU: baixa parcial, limite do saldo, importação repetida, conciliação sem duplicidade, estorno, parcelas únicas, entrada/arte/saldo e configuração' as resultado;
rollback;
