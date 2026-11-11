export const SESSION_KEY='avelon_access_gghclidwfawpniuwtuyy';
export const LEGACY_SESSION_KEY='avelon_session_gghclidwfawpniuwtuyy';
export const MAX_IDLE_MINUTES=14400;
export function validSessionRecord(record,now=Date.now()){
 return !!record?.session?.access_token&&!!record.session.refresh_token&&Number.isFinite(record.session.expires_at)&&Number.isFinite(record.lastActivity)&&Number.isInteger(record.idleMinutes)&&record.idleMinutes>=1&&record.idleMinutes<=MAX_IDLE_MINUTES&&now-record.lastActivity<=record.idleMinutes*60000;
}
export function createSessionStore({persistent,temporary,now=Date.now,uuid=()=>crypto.randomUUID()}){
 const get=(s,key)=>{try{return s.getItem(key)}catch{return null}};
 const put=(s,key,value)=>{try{s.setItem(key,JSON.stringify(value));return true}catch{return false}};
 const remove=(s,key)=>{try{s.removeItem(key)}catch{}};
 const parse=value=>{try{return JSON.parse(value)}catch{return null}};
 let current=null;
 function clear(){current=null;put(persistent,SESSION_KEY,{generation:uuid(),session:null});remove(temporary,SESSION_KEY);remove(temporary,LEGACY_SESSION_KEY)}
 function read(){
  const localRaw=get(persistent,SESSION_KEY),local=parse(localRaw),tab=parse(get(temporary,SESSION_KEY));
  let record=tab&&(!local||tab.generation===local.generation)?tab:local;
  if(!record&&!localRaw){const legacy=parse(get(temporary,LEGACY_SESSION_KEY));if(legacy?.access_token&&legacy.refresh_token){record={session:legacy,lastActivity:now(),idleMinutes:30,persistent:false,generation:uuid()};put(temporary,SESSION_KEY,record);put(persistent,SESSION_KEY,{generation:record.generation,session:null});remove(temporary,LEGACY_SESSION_KEY)}}
  if(validSessionRecord(record,now())){current=record;return record.session}
  if(record?.session){clear()}current=null;return null;
 }
 function write(session,{touch=true,policy}={}){
  if(!session){clear();return null}
  const existing=current,record={session,lastActivity:touch?now():(existing?.lastActivity??now()),idleMinutes:policy?.idleMinutes??existing?.idleMinutes??30,persistent:policy?.persistent??existing?.persistent??false,generation:existing?.generation??uuid()};
  if(!validSessionRecord(record,now())){clear();return null}
  if(record.persistent&&put(persistent,SESSION_KEY,record)){remove(temporary,SESSION_KEY)}else{record.persistent=false;put(temporary,SESSION_KEY,record);put(persistent,SESSION_KEY,{generation:record.generation,session:null})}
  remove(temporary,LEGACY_SESSION_KEY);current=record;return session;
 }
 function touch(){const session=read();if(!session)return null;if(now()-current.lastActivity>=15000)write(session,{touch:true});return session}
 return {read,write,touch,clear,get record(){return current}};
}
