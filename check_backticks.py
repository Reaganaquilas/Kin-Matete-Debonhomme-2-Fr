path = r'f:/APP/pdf.html'
with open(path, 'r', encoding='utf-8') as f:
    s = f.read()
count = s.count('`')
print('backtick count:', count)
pos = [i for i,c in enumerate(s) if c=='`']
if pos:
    print('last positions (up to 5):', pos[-5:])
    last = pos[-1]
    start = max(0, last-200)
    print('\nContext around last backtick:\n')
    print(s[start:last+200])
else:
    print('no backticks')
