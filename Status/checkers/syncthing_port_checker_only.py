import socket

def syncthing_service_exists(host, port):
    """Simple TCP connection test - no API auth needed."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2)
    result = sock.connect_ex((host, port))
    sock.close()
    return result == 0

# Use in checker:
# status="up" if service exists, "down" if port closed
