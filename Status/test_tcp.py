from checkers import tcp_checker
from pprint import pprint
import json

hosts_to_test = [
    "imagebeast",
    "chatworkhorse", 
    "travelbeast",
    "amsterdamdesktop",
    "denniss-macbook-air",
    "surface3-gc",
    "mathes-mac-mini",
    "denniss-2nd-macbook-air"
]

print("Testing all hosts with Tailscale ping:\n")
for host in hosts_to_test:
    try:
        result = tcp_checker.check(host, 3000)
        status_icon = "✅" if result['status'] == 'up' else "❌"
        print(f"{status_icon} {host:25s} | {result['status']:4s} |  {result['response_time_ms']:,}ms")
        if result.get('detail'):
            print(f"    → Detail: {result['detail']}")
    except Exception as e:
        print(f"❌ {host:25s} | ERROR: {e}")

