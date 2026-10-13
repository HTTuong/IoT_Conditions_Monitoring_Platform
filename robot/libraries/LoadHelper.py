import threading
from concurrent.futures import ThreadPoolExecutor

import requests


class LoadHelper:
    """Fires identical requests at the same instant to expose race conditions."""

    def post_concurrently(self, url, body, count=20):
        """POSTs ``body`` to ``url`` ``count`` times, all released together by a barrier.
        Returns the list of HTTP status codes."""
        count = int(count)
        payload = dict(body)
        barrier = threading.Barrier(count)

        def fire(_):
            barrier.wait(timeout=10)  # every thread waits here, then they all go at once
            return requests.post(url, json=payload, timeout=10).status_code

        with ThreadPoolExecutor(max_workers=count) as pool:
            return list(pool.map(fire, range(count)))