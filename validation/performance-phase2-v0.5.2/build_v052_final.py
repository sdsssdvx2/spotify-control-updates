from pathlib import Path
src=Path('validation/performance-phase2-v0.5.2/build_v052.py').read_text(encoding='utf-8')
old="    if b<0:b=s.find('\\ntry{',a+1)\n    assert b>a,name\n"
new="    if b<0:b=s.find('\\ntry{',a+1)\n    if b<0:b=len(s)\n    assert b>a,name\n"
assert src.count(old)==1,src.count(old)
src=src.replace(old,new,1)
exec(compile(src,'validation/performance-phase2-v0.5.2/build_v052.py','exec'),{'__name__':'__main__','__file__':'validation/performance-phase2-v0.5.2/build_v052.py'})
