import {configSection,productionStage,round} from './business.js?v=20261111-v15a';

export function orderPaymentPlan(ctx,quote,stage,{manual=false}={}){
 const total=Number(quote.total),cfg=configSection(ctx.settings,'production');
 const production=productionStage(stage,cfg.stages),final=stage==='completed';
 if(!manual&&!final&&configSection(ctx.settings,'budget').receipt_auto_on_production===false)return null;
 if(total<=0||(!manual&&(stage===quote.stage||(!production&&!final&&stage!=='awaiting_balance'))))return null;
 const paid=round(Number(ctx.orderFinance?.find(f=>f.quote_id===quote.id)?.paid||0));
 const valid=(ctx.paymentReceipts||[]).filter(r=>r.quote_id===quote.id&&!r.reversed&&r.kind!=='final');
 const issued=round(valid.reduce((sum,r)=>sum+Number(r.amount),0));
 const balance=round(Math.max(0,total-paid)),available=round(Math.max(0,paid-issued));
 const isBalance=final||['ready','awaiting_balance'].includes(stage);
 const deposit=round(Number(quote.production?.agreed_entry_amount??total*Number(quote.entry_percentage??50)/100));
 const target=isBalance?total:deposit,newAmount=round(Math.max(0,Math.min(balance,target-paid)));
 if(!manual&&final&&balance===0)return null;
 if(!manual&&!final&&newAmount===0&&available===0)return null;
 return {final,isBalance,total,paid,issued,balance,available,newAmount,deposit,receiptId:valid[0]?.id||null};
}

export function paymentConfirmation(plan,values){
 if(values.received!=='yes'&&values.received!=='no')throw Error('Informe se o cliente já pagou.');
 const record=values.received==='yes',amount=record?Number(values.amount):0;
 if(record){
  if(!Number.isFinite(amount)||amount<=0||Math.abs(amount-round(amount))>0.000001||amount>plan.balance)throw Error('Informe o valor recebido, até o saldo devedor.');
  if(!values.account)throw Error('Selecione a conta que recebeu o pagamento.');
  if(!/^\d{4}-\d{2}-\d{2}$/.test(values.paid_on||'')||!Number.isFinite(Date.parse(values.paid_on+'T12:00:00Z'))||new Date(values.paid_on+'T12:00:00Z').toISOString().slice(0,10)!==values.paid_on)throw Error('Informe a data correta do recebimento.');
  if(!values.method)throw Error('Selecione a forma de pagamento.');
 }
 if(plan.final&&round(plan.balance-amount)>0)throw Error('Para finalizar e emitir a quitação, confirme o recebimento de todo o saldo.');
 return {p_received:record,p_amount:amount,p_account:record?values.account:null,p_paid_on:record?values.paid_on:null,p_method:record?values.method:'',p_message:values.message||''};
}
