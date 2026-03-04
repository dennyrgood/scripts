from checkers.tcp_checker import check
for port in [5000, 5001, 5005, 8080]:
    r = check('127.0.0.1', 5000, port=port)
    status = r['status']
    ms = r['response_time_ms']
    print(f':{port} -> {status} {ms}ms')