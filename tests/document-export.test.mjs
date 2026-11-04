import test from 'node:test';
import assert from 'node:assert/strict';
import {install} from '../dist/js/core/document-pdf.js';

// Test the user-visible export flow without launching a system share target.
function fixture({shareError,markError}={}){
 const listeners=new Map(),buttons=new Map();let downloads=0,exports=0;
 const element=()=>({isConnected:true,disabled:false,textContent:'',append(){},remove(){},setAttribute(){},removeAttribute(){},querySelectorAll(){return []},addEventListener(type,fn){this[type]=fn},click(){return this.clickHandler?.()}});
 const download=element();download.addEventListener=(_,fn)=>{download.clickHandler=()=>fn({preventDefault(){},currentTarget:download})};
 const native=element(),error=element();native.addEventListener=(_,fn)=>{native.clickHandler=()=>fn({currentTarget:native})};
 const modal={querySelector:s=>s==='#pdf-download'?download:s==='#pdf-native-share'?native:error,addEventListener:(event,fn)=>listeners.set(event,fn)};
 const article={cloneNode:()=>element()};
 const document={fonts:{ready:Promise.resolve()},styleSheets:[],head:{append(){}},body:{append(){}},querySelector:()=>article,getElementById:id=>buttons.get(id),createElement:tag=>{const el=element();el.style={};if(tag==='a')el.click=()=>{downloads++};return el}};
 const window={html2pdf:()=>({set(){return this},from(){return this},outputPdf:async()=>new Blob(['x'.repeat(200)],{type:'application/pdf'})})};
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{canShare:()=>true,share:async()=>{if(shareError)throw shareError}}});
 globalThis.document=document;globalThis.window=window;
 const ctx={esc:s=>s,modal:()=>modal,toast:()=>{}};install(ctx);
 return {ctx,download,native,error,get downloads(){return downloads},get exports(){return exports},onExport:async()=>{if(markError)throw Error('offline');exports++}};
}
test('preparar PDF não envia; cancelar compartilhamento mantém rascunho',async()=>{
 const f=fixture({shareError:Object.assign(Error('cancelado'),{name:'AbortError'})});await f.ctx.shareDocument({filename:'teste.pdf',title:'Teste',authorize:async()=>{},onExport:f.onExport});assert.equal(f.exports,0);await f.native.click();assert.equal(f.exports,0);assert.equal(f.error.textContent,'');
});
test('compartilhamento concluído e download acionam atualização',async()=>{
 const f=fixture();await f.ctx.shareDocument({filename:'teste.pdf',title:'Teste',authorize:async()=>{},onExport:f.onExport});await f.native.click();assert.equal(f.exports,1);await f.download.click();assert.equal(f.exports,2);assert.equal(f.downloads,1);
});
test('falha ao atualizar não inicia download nem oculta erro',async()=>{
 const f=fixture({markError:true});await f.ctx.shareDocument({filename:'teste.pdf',title:'Teste',authorize:async()=>{},onExport:f.onExport});await f.download.click();assert.equal(f.downloads,0);assert.match(f.error.textContent,/Não foi possível atualizar/);
});
