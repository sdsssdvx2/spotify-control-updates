from pathlib import Path
import hashlib,json,re,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
BASE='29d6c52c6a79559e513b367ec57edcccebae5fd0'
MAIN=(281585,'e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18')
ADDON=(225044,'3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86')

KEYWORDS=[
 'ivlyrics','tagify','splitify','cover ambience','sc cover','marketplace','pithaya',
 'customapp','custom app','extension','theme','addon','autoapp','auto app',
 'registry','source','revision','version','rollback','backup','transaction','pending',
 'github','release','commit','sha256','digest','provenance','install','update',
 'rating','ratings','star rating','star ratings','note','notes','playlist','sync'
]
GENERIC_REGISTRY_MARKERS=[
 'registry.json','sources.json','addons.json','managed-addons','managed_addons',
 'source_registry','source registry','addon registry','customapp registry','extension registry'
]

def sha(b):return hashlib.sha256(b).hexdigest()
def identity(path,expected,label):
 b=path.read_bytes(); actual=(len(b),sha(b))
 if actual!=expected:raise RuntimeError(f'{label} identity drift {actual} != {expected}')
 return b

def function_blocks(text):
 starts=list(re.finditer(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text))
 out=[]
 for i,m in enumerate(starts):
  end=starts[i+1].start() if i+1<len(starts) else len(text)
  out.append((m.group(1),text.count('\n',0,m.start())+1,text[m.start():end]))
 return out

def main():
 if subprocess.check_output(['git','merge-base',BASE,'HEAD'],text=True).strip()!=BASE:
  raise RuntimeError('wrong production merge base')
 subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.20/build_v0620.py'),'--build'],cwd=ROOT)
 out=ROOT/'validation/v0.6.20/out/bin'
 identity(out/'spotify-control.ps1',MAIN,'production main')
 addon_bytes=identity(out/'addon-manager.ps1',ADDON,'production addon')
 text=addon_bytes.decode('utf-8-sig')
 low=text.lower()
 funcs=[]
 for name,line,block in function_blocks(text):
  l=(name+'\n'+block).lower()
  hits=sorted({k for k in KEYWORDS if k in l})
  if hits:
   urls=sorted(set(re.findall(r'https?://[^\s\"\'\)]+',block)))
   funcs.append({'name':name,'start_line':line,'length':len(block),'keyword_hits':hits,'urls':urls,'excerpt':block[:18000]})
 lines=[]
 for i,row in enumerate(text.splitlines(),1):
  l=row.lower()
  hits=sorted({k for k in KEYWORDS if k in l})
  if hits: lines.append({'line':i,'keyword_hits':hits,'text':row[:1400]})
 urls=sorted(set(re.findall(r'https?://[^\s\"\'\)]+',text)))
 literals={k:text.lower().count(k) for k in KEYWORDS}
 generic={k:(k in low) for k in GENERIC_REGISTRY_MARKERS}
 app_names={
  'ivlyrics':bool(re.search(r'ivlyrics',text,re.I)),
  'tagify':bool(re.search(r'tagify',text,re.I)),
  'splitify':bool(re.search(r'splitify',text,re.I)),
  'sc_cover_ambience':bool(re.search(r'(sc[ -]?cover[ -]?ambience|cover[ -]?ambience)',text,re.I)),
  'marketplace':bool(re.search(r'marketplace',text,re.I)),
  'pithaya':bool(re.search(r'pithaya',text,re.I)),
 }
 state_markers=[]
 for pat in [r'Join-Path[^\n]{0,220}(json|state|backup|transaction|pending|registry)',r'\$[^\s=]*(State|Registry|Backup|Transaction|Pending)[^\s=]*\s*=']:
  for m in re.finditer(pat,text,re.I): state_markers.append(m.group(0)[:500])
 report={
  'schema':1,'audit':'addon-roadmap-audit-v0.1.0','result':'AUDIT_PASS',
  'production_base':BASE,'validation_head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
  'production_addon':{'size':ADDON[0],'sha256':ADDON[1]},
  'function_count':len(function_blocks(text)),'matched_functions':funcs,
  'matched_lines':lines,'urls':urls,'keyword_counts':literals,
  'generic_registry_markers':generic,'known_app_presence':app_names,
  'state_markers':state_markers[:120],
 }
 (ROOT/'addon-roadmap-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
 print('ADDON_ROADMAP_AUDIT_PASS functions=%d matched=%d lines=%d urls=%d' % (report['function_count'],len(funcs),len(lines),len(urls)))
 print('known_apps',app_names)
 print('generic_registry_markers',generic)

if __name__=='__main__':main()
