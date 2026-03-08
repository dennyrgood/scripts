import urllib.request
import urllib.error
import time

url = "https://ollama-lite.ldmathes.cc"  # change as needed

print(f"Testing: {url}")

start = time.monotonic()
try:
    req = urllib.request.Request(url, headers={"User-Agent": "Test/1.0"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        elapsed = round((time.monotonic() - start) * 1000)
        print(f"Status:  UP")
        print(f"HTTP:    {resp.status}")
        print(f"Time:    {elapsed}ms")
        body = resp.read(200)
        print(f"Body:    {body}")

except urllib.error.HTTPError as e:
    elapsed = round((time.monotonic() - start) * 1000)
    print(f"HTTP Error: {e.code}")
    print(f"Time: {elapsed}ms")

except Exception as e:
    elapsed = round((time.monotonic() - start) * 1000)
    print(f"Failed: {type(e).__name__}: {e}")
    print(f"Time: {elapsed}ms")

input("Press Enter to close...")