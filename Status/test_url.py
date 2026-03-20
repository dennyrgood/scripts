import sys
sys.path.insert(0, '.')  # so it can find the checkers folder

from checkers import http_checker

url = "https://ollama.ldmathes.cc"  # swap in whatever URL is failing

result = http_checker.get(url, timeout_ms=5000)

print(f"Status:       {result['status']}")
print(f"HTTP Code:    {result['http_code']}")
print(f"Response ms:  {result['response_time_ms']}")
print(f"Detail:       {result['detail']}")
print(f"Timestamp:    {result['timestamp_utc']}")
if result['raw_body']:
    print(f"Body preview: {result['raw_body'][:200]}")