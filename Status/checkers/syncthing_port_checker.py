import socket

def check_port(host, port, timeout=2):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    result = sock.connect_ex((host, port))
    sock.close()
    return "OPEN" if result == 0 else "CLOSED"

print(f"surface3-gc:8384: {check_port('surface3-gc', 8384)}")
print(f"mathes-mac-mini:8384: {check_port('mathes-mac-mini', 8384)}")
