/** v19 R2 gateway. Bind your EXISTING bucket (MEDIA_BUCKET or MY_BUCKET). No bucket migration.
 * POST / + X-File-Name uploads; GET/HEAD /<key> reads.
 * DELETE / JSON {url} + X-R2-Delete-Protocol:r2-delete-v1 verifies bucket.head after deletion.
 * Optional R2_PUBLIC_ORIGINS: comma-separated origins serving THIS same bucket.
 * Legacy DELETE X-File-Name remains supported; header keys are NOT double-decoded.
 */
const PROTOCOL = 'r2-delete-v1';
// Public base URL that stored file URLs use (R2.dev / custom domain of THIS SAME bucket). Empty = Worker origin.
const PUBLIC_BASE_URL = '';
const CORS = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET, HEAD, POST, DELETE, OPTIONS','Access-Control-Allow-Headers':'Content-Type, X-File-Name, X-File-Type, X-R2-Delete-Protocol','Access-Control-Max-Age':'86400'};
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{...CORS,'Content-Type':'application/json','Cache-Control':'no-store'}});
const validKey=key=>typeof key==='string'&&key.length>0&&!key.includes('\0');
export default {
 async fetch(request,env,ctx){
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers:CORS});
  const bucket=env.MEDIA_BUCKET||env.MY_BUCKET;if(!bucket)return json({error:'R2 bucket binding (MEDIA_BUCKET or MY_BUCKET) is missing'},500);
  const endpoint=new URL(request.url);
  try{
   if(request.method==='POST'){
    const key=(request.headers.get('X-File-Name')||'').replace(/^\/+/, '');
    if(!validKey(key))return json({error:'X-File-Name header required'},400);
    await bucket.put(key,request.body,{httpMetadata:{contentType:request.headers.get('X-File-Type')||'application/octet-stream'}});
    const base=(PUBLIC_BASE_URL||endpoint.origin).replace(/\/+$/,'');return json({url:`${base}/${key.split('/').map(encodeURIComponent).join('/')}`,key});
   }
   if(request.method==='DELETE'){
    let key,sourceUrl='';
    if(request.headers.get('X-R2-Delete-Protocol')===PROTOCOL){
     const body=await request.json();sourceUrl=body.url;
     if(typeof sourceUrl!=='string')return json({error:'A media URL is required'},400);
     const media=new URL(sourceUrl);
     const allowed=new Set([endpoint.origin,...(PUBLIC_BASE_URL?[new URL(PUBLIC_BASE_URL).origin]:[]),...String(env.R2_PUBLIC_ORIGINS||'').split(',').map(x=>x.trim()).filter(Boolean)]);
     if(!['http:','https:'].includes(media.protocol)||media.username||media.password||!allowed.has(media.origin))return json({error:'Media URL is not on this gateway. Set PUBLIC_BASE_URL / R2_PUBLIC_ORIGINS only for aliases of this SAME bucket.'},409);
     key=decodeURIComponent(media.pathname.replace(/^\/+/,''));
    }else{
     const header=request.headers.get('X-File-Name');
     key=header!==null?header.replace(/^\/+/, ''):decodeURIComponent(endpoint.pathname.replace(/^\/+/,''));
    }
    if(!validKey(key))return json({error:'An exact object key is required'},400);
    const before=await bucket.head(key);
    if(before)await bucket.delete(key);
    if(await bucket.head(key))return json({error:'R2 object still exists; deletion was not verified',key},502);
    if(ctx&&typeof caches!=='undefined'){
     const origins=new Set([endpoint.origin]);if(sourceUrl)origins.add(new URL(sourceUrl).origin);
     const paths=[...origins].map(origin=>`${origin}/${key.split('/').map(encodeURIComponent).join('/')}`);
     ctx.waitUntil(Promise.all(paths.map(u=>caches.default.delete(new Request(u)).catch(()=>false))));
    }
    return json({ok:true,deleteProtocol:PROTOCOL,absent:true,key,sourceUrl,removed:!!before});
   }
   if(request.method==='GET'||request.method==='HEAD'){
    const key=decodeURIComponent(endpoint.pathname.replace(/^\/+/,''));
    if(!key)return json({ok:true,service:'zedge r2 gateway',deleteProtocol:PROTOCOL});
    const obj=request.method==='HEAD'?await bucket.head(key):await bucket.get(key);
    if(!obj)return json({error:'not found'},404);
    const headers=new Headers(CORS);obj.writeHttpMetadata(headers);headers.set('etag',obj.httpEtag);headers.set('Cache-Control','no-cache, max-age=0, must-revalidate');
    return new Response(request.method==='HEAD'?null:obj.body,{headers});
   }
   return json({error:'method not allowed'},405);
  }catch(e){return json({error:e instanceof Error?e.message:'R2 request failed'},500);}
 }
};
