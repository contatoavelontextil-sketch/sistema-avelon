import {install as installPermissionEditor} from './modules/permission-editor.js';
import {install as installPermissions} from './core/permissions.js';
import {config} from '../config.js';
import {install as install0} from './core/utils.js';
import {install as install1} from './core/session.js';
import {install as install2} from './services/supabase.js';
import {install as install3} from './auth/auth.js';
import {install as install4} from './components/layout.js';
import {install as install5} from './modules/clients-products.js';
import {install as install6} from './modules/quotes.js';
import {install as install7} from './modules/users.js';
import {install as install8} from './modules/settings.js';

const ctx={config,session:null,clients:[],products:[],quotes:[],current:'home',draft:[],viewQuote:null,profile:null,settings:{}};
try{ctx.session=JSON.parse(sessionStorage.getItem('avelon_session_gghclidwfawpniuwtuyy')||'null')}catch{sessionStorage.removeItem('avelon_session_gghclidwfawpniuwtuyy')}
install0(ctx);
install1(ctx);
install2(ctx);
install3(ctx);
install4(ctx);
install5(ctx);
install6(ctx);
install7(ctx);
install8(ctx);
installPermissions(ctx);
installPermissionEditor(ctx);
ctx.start();
