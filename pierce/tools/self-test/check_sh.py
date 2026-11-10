import re
import sys

src = open(sys.argv[1], encoding='utf-8').read()
lines = src.splitlines()

# 1) 剔除 heredoc 正文（保留行号）
masked = []
i = 0
while i < len(lines):
    L = lines[i]
    m = re.search(r"<<'([A-Z_]+)'", L)
    if m:
        tag = m.group(1)
        masked.append(L)
        i += 1
        while i < len(lines) and lines[i].strip() != tag:
            masked.append('')
            i += 1
        if i < len(lines):
            masked.append(lines[i])
            i += 1
        continue
    masked.append(L)
    i += 1

text = '\n'.join(masked)

# 2) 抹掉所有单/双引号字符串内容（含跨行的 python -c '...'），避免误判
text = re.sub(r"'[^']*'", "''", text, flags=re.S)
text = re.sub(r'"[^"]*"', '""', text, flags=re.S)

scan = text.split('\n')

stack = []
problems = []
WORD = r'(?<![\w-])(if|fi|for|while|until|do|done|case|esac)(?![\w-])'

for idx, raw in enumerate(scan, start=1):
    line = raw.strip()
    if not line or line.startswith('#'):
        continue
    code = re.sub(r'\s+#.*$', '', raw)
    for m in re.finditer(WORD, code):
        w = m.group(1)
        if w in ('if', 'for', 'while', 'until'):
            stack.append([w, idx])
        elif w == 'case':
            stack.append(['case', idx])
        elif w == 'fi':
            if stack and stack[-1][0] == 'if':
                stack.pop()
            else:
                problems.append('line %d: fi 无对应 if（栈顶=%s）' % (idx, stack[-1] if stack else None))
        elif w == 'done':
            if stack and stack[-1][0] in ('for', 'while', 'until'):
                stack.pop()
            else:
                problems.append('line %d: done 无对应循环（栈顶=%s）' % (idx, stack[-1] if stack else None))
        elif w == 'esac':
            if stack and stack[-1][0] == 'case':
                stack.pop()
            else:
                problems.append('line %d: esac 无对应 case（栈顶=%s）' % (idx, stack[-1] if stack else None))

for kind, ln in stack:
    problems.append('未闭合: %s (line %d)' % (kind, ln))

# 3) 引号与 $() 平衡（抹掉字符串后仍应成对）
q = text.count("'")
print('quote_remnant(kind):', q)

if problems:
    print('问题:')
    for p in problems:
        print('  ' + p)
    sys.exit(1)
print('结构检查通过：if/for/while/case 全部配对')
