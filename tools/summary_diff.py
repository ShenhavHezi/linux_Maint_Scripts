#!/usr/bin/env python3
import sys, re, json
from pathlib import Path

def parse_line(line: str):
    parts=line.strip().split()
    d={}
    for p in parts:
        if '=' in p:
            k,v=p.split('=',1)
            d[k]=v
    return d

def load_summary(path: Path):
    rows=[]
    if not path.exists():
        return rows
    for line in path.read_text(errors='ignore').splitlines():
        if line.startswith('monitor='):
            rows.append(parse_line(line))
    return rows

def key(row):
    return (row.get('monitor',''), row.get('host',''))

def main(prev_path, cur_path, fmt='text'):
    prev=load_summary(Path(prev_path))
    cur=load_summary(Path(cur_path))
    prev_map={key(r): r for r in prev}
    cur_map={key(r): r for r in cur}

    new_fail=[]
    recovered=[]
    changed=[]
    still_bad=[]

    def sev(st):
        return {'OK':0,'SKIP':0,'WARN':1,'CRIT':2,'UNKNOWN':3}.get(st,3)

    for k, r in cur_map.items():
        prev_r = prev_map.get(k)
        cur_st=r.get('status','UNKNOWN')
        prev_st=prev_r.get('status','MISSING') if prev_r else 'MISSING'

        if prev_r is None:
            # new entity
            if cur_st != 'OK':
                changed.append({'type':'new', 'key':k, 'prev':None, 'cur':r})
            continue

        if prev_st != cur_st:
            # transition
            if prev_st == 'OK' and cur_st in ('WARN','CRIT','UNKNOWN'):
                new_fail.append((k, prev_r, r))
            elif prev_st in ('WARN','CRIT','UNKNOWN') and cur_st == 'OK':
                recovered.append((k, prev_r, r))
            else:
                changed.append({'type':'transition', 'key':k, 'prev':prev_r, 'cur':r})
        else:
            if cur_st in ('WARN','CRIT','UNKNOWN'):
                still_bad.append((k, r))

    # sort: by severity desc then monitor/host
    new_fail.sort(key=lambda x: (-sev(x[2].get('status','UNKNOWN')), x[0]))
    recovered.sort(key=lambda x: (x[0]))
    still_bad.sort(key=lambda x: (-sev(x[1].get('status','UNKNOWN')), x[0]))

    if fmt=='json':
        out={
            'new_failures':[{'monitor':k[0],'host':k[1],'prev':p,'cur':c} for k,p,c in new_fail],
            'recovered':[{'monitor':k[0],'host':k[1],'prev':p,'cur':c} for k,p,c in recovered],
            'still_bad':[{'monitor':k[0],'host':k[1],'cur':c} for k,c in still_bad],
            'changed':changed,
        }
        print(json.dumps(out, indent=2, sort_keys=True))
        return 0

    def brief(row):
        st=row.get('status','?')
        reason=row.get('reason','')
        extra=''
        if reason:
            extra=f" reason={reason}"
        return f"{st}{extra}"

    print(f"diff_prev={prev_path}")
    print(f"diff_cur={cur_path}")
    print("")

    print(f"NEW_FAILURES {len(new_fail)}")
    for k,p,c in new_fail[:80]:
        print(f"- {k[1]} {k[0]}: {brief(p)} -> {brief(c)}")

    print("")
    print(f"RECOVERED {len(recovered)}")
    for k,p,c in recovered[:80]:
        print(f"- {k[1]} {k[0]}: {brief(p)} -> {brief(c)}")

    print("")
    print(f"STILL_BAD {len(still_bad)}")
    for k,c in still_bad[:120]:
        print(f"- {k[1]} {k[0]}: {brief(c)}")

    return 0

if __name__=='__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <prev_summary> <cur_summary> [--json]", file=sys.stderr)
        sys.exit(2)
    prev=sys.argv[1]; cur=sys.argv[2]
    fmt='json' if (len(sys.argv)>3 and sys.argv[3]=='--json') else 'text'
    sys.exit(main(prev, cur, fmt))
