#!/usr/bin/env python3
import os

file2 = 'stemcell.txt'

def fn(s):
    while s.endswith('.0'):
        s = s[:-2]
    return s

try:
    os.remove(file2)
except:
    pass

files = os.listdir('releases')
releases = filter(lambda x:x.endswith('.tgz'),files)
for r in releases:
    r = r.replace('.tgz','')
    l = r.split('-')
    with open(file2,'w') as f:
        f.write(fn(l[-1]))
    break
