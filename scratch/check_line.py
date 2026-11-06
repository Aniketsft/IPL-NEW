with open(r'd:\enterprise_auth_system\frontend\lib\features\logistics\presentation\pages\sales_invoice\transaction_history_screen.dart', 'rb') as f:
    lines = f.readlines()
for i in range(704, 712):
    print(i+1, repr(lines[i]))
