import {configSection,productionStage} from './business.js?v=20261111-v15a';
export const READY_MESSAGE="Olá! 😊\n\nPassando para avisar que seu pedido #{pedido} já está pronto. 👕✨\n\nVocê já pode retirar seu pedido ou, se preferir, podemos combinar a forma de entrega.\n\nCaso ainda haja valor pendente, o pagamento poderá ser realizado no momento da retirada ou antes do envio, no mesmo Pix utilizado para o adiantamento de {entrada_percentual}%.\n\nAssim que o pagamento for confirmado, envio o seu recibo também. 😉\n\nAgradecemos por escolher a {empresa}. Foi um prazer produzir seu personalizado! 🙏\n\nInstagram: @avelon_textil\nWhatsApp: (38) 9 8816-9968";
export function readyMessage(template,values){return (template||READY_MESSAGE).replace(/\{(cliente|pedido|empresa|saldo|entrada_percentual)\}/g,(_,key)=>String(values[key]??''))}
export async function saveOrderTransition(ctx,quote,change,request){
 if(change.p_stage==='completed'){
  if(!ctx.can('receipts','create')||!ctx.can('receipts','view'))throw Error('Para finalizar com recibo, seu acesso precisa permitir consultar e emitir recibos. Solicite a liberação ao Mestre Criador.');
  if(Number(quote.total)<=0)throw Error('O recibo final exige um pedido com valor e quitação registrada no Financeiro.');
  const note=['production','cutting','personalization','sewing'].includes(quote.stage)?'Finalização direta, sem passagem registrada pelas etapas intermediárias.':'';return {receipt:await ctx.rpc('complete_order_with_receipt',{...change,p_note:note,p_request:request})};
 }
 const cfg=configSection(ctx.settings,'production');
 if(Number(quote.total)>0&&productionStage(change.p_stage,cfg.stages)&&!productionStage(quote.stage,cfg.stages)&&configSection(ctx.settings,'budget').receipt_auto_on_production&&ctx.can('receipts','create'))return {advance:true};
 await ctx.rpc('update_order',change);
 return {ready:change.p_stage==='ready'&&quote.stage!=='ready'};
}
