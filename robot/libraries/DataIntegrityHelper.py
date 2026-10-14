import threading

import requests


def register_concurrently(base_url, device_id, count=10):
    """Fire `count` identical POST /devices requests at the same instant; return the status codes."""
    count = int(count)
    barrier = threading.Barrier(count)
    codes = [None] * count

    def worker(index):
        barrier.wait()
        try:
            response = requests.post(
                f"{base_url}/devices",
                json={"device_id": device_id, "name": "race"},
                timeout=10,
            )
            codes[index] = response.status_code
        except requests.RequestException:
            codes[index] = -1

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(count)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return codes