# plant.py NAME FILE OLDFILE NEWFILE : copy the tree to build/m3cr-b/mut/NAME, replace OLD (exactly once) with NEW in FILE
import sys,os,subprocess
root=os.getcwd()  # run from the tree's root
name,f,oldf,newf=sys.argv[1:5]
old=open(oldf).read().rstrip('\n'); new=open(newf).read().rstrip('\n')
dst=os.path.join(root,'build/m3cr-b/mut',name)
os.makedirs(dst,exist_ok=True)
subprocess.run(['rsync','-a','--exclude','.git','--exclude','build',root+'/',dst+'/'],check=True)
p=os.path.join(dst,f)
s=open(p).read()
n=s.count(old)
if n!=1:
    print(f'{name}: OLD occurs {n} times in {f}'); sys.exit(1)
open(p,'w').write(s.replace(old,new))
r=subprocess.run(['diff',os.path.join(root,f),p],capture_output=True,text=True)
print(f'== {name}: {f}'); print(r.stdout)
