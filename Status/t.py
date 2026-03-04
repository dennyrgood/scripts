import sys
sys.path.insert(0, '.')
from config import FLEET, TIMEOUT_TCP_MS, CHECKER_HOST
from checkers import tcp_checker
m = next(x for x in FLEET if x['tailscale_name'] == 'chatworkhorse')
print('probe_port:', m.get('probe_port', 80))
name = m['tailscale_name']
probe_host = '127.0.0.1' if name == CHECKER_HOST else name
print('probe_host:', probe_host)
result = tcp_checker.check(probe_host, TIMEOUT_TCP_MS, port=m.get('probe_port', 80))
print(result)