# -*- coding: utf-8 -*-
"""设定数据静态校验（Godot 不可用时的替代验证）：
JSON 语法、正典条数、知识-正典逐字匹配（REF 消解）、场景图连通性、引用完整性。"""
import json, sys, io, os
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = os.path.join(ROOT, 'settings')
errors = []

def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)

# 1. 全部 JSON 语法
all_json = []
for sub in ['', 'characters', 'scenes', 'memory']:
    d = os.path.join(S, sub)
    for name in os.listdir(d):
        if name.endswith('.json'):
            all_json.append(os.path.join(d, name))
for p in all_json:
    try:
        load(p)
    except Exception as e:
        errors.append('JSON 语法错误: %s: %s' % (p, e))
print('JSON 文件数:', len(all_json))

canon = load(os.path.join(S, 'canon.json'))['facts']
factions = load(os.path.join(S, 'factions.json'))['factions']
chars = {}
for name in os.listdir(os.path.join(S, 'characters')):
    c = load(os.path.join(S, 'characters', name))
    chars[c['id']] = c
scenes = {}
for name in os.listdir(os.path.join(S, 'scenes')):
    s = load(os.path.join(S, 'scenes', name))
    scenes[s['id']] = s
memories = [load(os.path.join(S, 'memory', n)) for n in os.listdir(os.path.join(S, 'memory'))]

# 2. 正典计数
majors = [f for f in canon if f['weight'] == 'major']
global_minors = [f for f in canon if f['weight'] == 'minor' and not f.get('scope')]
print('正典总数:', len(canon), '| major:', len(majors), '| 全局 minor:', len(global_minors))
if len(canon) != 53: errors.append('正典总数 != 53')
if len(majors) != 9: errors.append('major != 9')
if len(global_minors) != 3: errors.append('全局 minor != 3')
digest = len(majors) + len(global_minors)
print('全局提要(测试断言):', digest)
if digest != 12: errors.append('全局提要 != 12')
for f in canon:
    if len(f['content'].strip()) == 0: errors.append('正典空表述')

# 3. 知识-正典逐字匹配（REF 消解率）
canon_texts = set(f['content'] for f in canon)
total_k, ref_k = 0, 0
for cid, c in chars.items():
    for k in c.get('knowledge', []):
        total_k += 1
        if k['content'] in canon_texts:
            ref_k += 1
print('人物知识总条数:', total_k, '| 与正典逐字一致(会转为 REF):', ref_k)
if ref_k < 40: errors.append('REF 消解数过低: %d' % ref_k)

# 4. wen_xu 关键断言（smoke/engine_loop 依赖）
wx = chars['wen_xu']
voided = [k for k in wx['knowledge'] if k['trust'] == '已失效']
print('wen_xu 知识:', len(wx['knowledge']), '| 已失效:', len(voided), '| 第10条信任:', wx['knowledge'][9]['trust'])
if len(wx['knowledge']) != 14: errors.append('wen_xu 知识 != 14')
if len(voided) != 1: errors.append('wen_xu 已失效 != 1')
if wx['knowledge'][9]['trust'] != '怀疑': errors.append('wen_xu 第10条非怀疑(engine_loop ref10 断言依赖)')

# 5. 场景图：links 对称 + 连通 + npcs/factions 引用存在
all_ids = set(chars) | set(scenes) | set(f['id'] for f in factions) | {'player'}
edges = set()
for sid, s in scenes.items():
    for npc in s.get('npcs', []):
        if npc not in chars: errors.append('场景 %s 引用不存在的人物 %s' % (sid, npc))
    for other in s.get('links', []):
        if other not in scenes: errors.append('场景 %s 链接不存在的地点 %s' % (sid, other))
        edges.add(tuple(sorted((sid, other))))
for c in chars.values():
    for fid in c.get('factions', []):
        if fid not in set(f['id'] for f in factions):
            errors.append('人物 %s 引用不存在的组织 %s' % (c['id'], fid))
adj = {sid: set() for sid in scenes}
for a, b in edges:
    adj[a].add(b); adj[b].add(a)
seen_set, stack = set(), [next(iter(scenes))]
while stack:
    n = stack.pop()
    if n in seen_set: continue
    seen_set.add(n)
    stack.extend(adj[n] - seen_set)
print('场景数:', len(scenes), '| 无向边数:', len(edges), '| 连通覆盖:', len(seen_set))
if len(seen_set) != len(scenes): errors.append('场景图不连通: %s' % (set(scenes) - seen_set))

# 6. 别名/规范名唯一性（提及扫描的闭集前提）
names = {}
for eid, e in list(chars.items()) + list(scenes.items()):
    for n in [e.get('name', '')] + e.get('aliases', []):
        if n in names: errors.append('名字重复: %s (%s / %s)' % (n, names[n], eid))
        names[n] = eid

# 7. 组织成员表姓名与人物卡匹配（职位解析依赖）
member_names = {m['name'] for f in factions for m in f['members']}
card_names = set(c['name'] for c in chars.values())
unmatched = {n for n in member_names if n not in card_names and n != '市长'}
print('组织成员姓名总数:', len(member_names), '| 无卡成员(配角):', unmatched or '无')

# 8. 记忆文件 npc_id 均存在
for m in memories:
    if m['npc_id'] not in chars: errors.append('记忆引用不存在的人物 %s' % m['npc_id'])
print('记忆文件数:', len(memories))

print()
if errors:
    print('==== 失败 %d 项 ====' % len(errors))
    for e in errors: print(' -', e)
    sys.exit(1)
print('==== 静态校验全部通过 ====')
