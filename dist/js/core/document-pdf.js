// Documents are rendered locally. Only the user-selected share target receives the file.
let library;
function loadLibrary(){
 if(window.html2pdf)return Promise.resolve();
 if(!library)library=new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=new URL('../../vendor/html2pdf-0.14.0.bundle.min.js',import.meta.url).href;s.onload=resolve;s.onerror=()=>{s.remove();library=null;reject(new Error('Não foi possível preparar o PDF. Tente novamente ou use Imprimir / Salvar PDF.'))};document.head.append(s)});
 return library;
}
function printRules(){
 const rules=[];
 function collect(list,inPrint=false){for(const rule of list){if(rule.type===3){try{collect(rule.styleSheet.cssRules,inPrint)}catch{}}else if(rule.type===4){if(rule.conditionText==='print')collect(rule.cssRules,true)}else if(inPrint&&rule.selectorText){rules.push(rule.selectorText.split(',').map(s=>'.pdf-export '+s.trim()).join(',')+'{'+rule.style.cssText+'}')}}}
 for(const sheet of document.styleSheets){try{collect(sheet.cssRules)}catch{}}
 return rules.join('\n');
}
async function renderPDF(article,filename){
 await loadLibrary();await document.fonts.ready;
 const host=document.createElement('div');host.className='pdf-export';
 const style=document.createElement('style');style.textContent=printRules();
 const copy=article.cloneNode(true);copy.querySelectorAll('[id]').forEach(e=>e.removeAttribute('id'));
 host.append(style,copy);const staging=document.createElement('div');staging.style.cssText='position:fixed;left:-10000px;top:0;pointer-events:none';staging.setAttribute('aria-hidden','true');staging.append(host);document.body.append(staging);
 try{
  await Promise.all([...copy.querySelectorAll('img')].map(img=>img.decode().catch(()=>{throw new Error('Uma imagem do documento não carregou. Aguarde e tente novamente.')})));
  const blob=await window.html2pdf().set({margin:15,filename,image:{type:'jpeg',quality:0.96},enableLinks:false,pagebreak:{mode:['css'],avoid:['tr','header','.document-signature','.receipt-totals','.receipt-value','.receipt-status-grid']},html2canvas:{scale:2,backgroundColor:'#ffffff',useCORS:true,logging:false,windowWidth:1024,scrollY:0},jsPDF:{unit:'mm',format:'a4',orientation:'portrait',compress:true}}).from(host).outputPdf('blob');
  if(blob.size<100)throw new Error('Não foi possível gerar o PDF. Use Imprimir / Salvar PDF.');
  return new File([blob],filename,{type:'application/pdf'});
 }finally{staging.remove()}
}
export function install(ctx){
 let preparing=false;
 ctx.shareDocument=async({filename,title,authorize,button})=>{
  if(preparing)return;preparing=true;if(button){button.disabled=true;button.textContent='Preparando PDF…'}
  try{
   await authorize();const article=document.querySelector('article.quote-print');if(!article)throw new Error('Abra o documento e tente novamente.');
   const file=await renderPDF(article,filename),url=URL.createObjectURL(file);
   let canShare=false;try{canShare=!!navigator.share&&!!navigator.canShare?.({files:[file]})}catch{}
   const d=ctx.modal('PDF pronto para enviar',`<p><strong>${ctx.esc(filename)}</strong></p><p class="muted">${canShare?'Toque em Compartilhar PDF e escolha WhatsApp, e-mail ou outro aplicativo disponível no seu aparelho.':'Este navegador não oferece compartilhamento de arquivos. Baixe o PDF e anexe no WhatsApp, e-mail ou outro aplicativo.'}</p><p class="helper muted">Confira o destinatário no aplicativo escolhido antes de enviar.</p><p role="alert" class="form-error" id="pdf-share-error"></p><div class="form-actions">${canShare?'<button class="primary" id="pdf-native-share">Compartilhar PDF</button>':''}<a class="button secondary" id="pdf-download">Baixar PDF</a><button class="secondary" data-close>Fechar</button></div>`);
   const download=d.querySelector('#pdf-download');download.href=url;download.download=filename;
   d.addEventListener('close',()=>{setTimeout(()=>URL.revokeObjectURL(url),60000)},{once:true});
   d.querySelector('#pdf-native-share')?.addEventListener('click',async e=>{
    const b=e.currentTarget;b.disabled=true;d.querySelector('#pdf-share-error').textContent='';
    try{await navigator.share({files:[file],title})}catch(error){if(error.name!=='AbortError')d.querySelector('#pdf-share-error').textContent='O compartilhamento não está disponível agora. Tente novamente ou baixe o PDF para enviar.'}finally{b.disabled=false}
   });
  }catch(e){ctx.toast(e.message)}finally{preparing=false;if(button?.isConnected){button.disabled=false;button.textContent='Compartilhar PDF'}}
 };
}
