"""Small single-process sliding-window limiter for authentication endpoints."""

from __future__ import annotations

import math
import time
from collections import defaultdict, deque
from threading import Lock


class RateLimitExceeded(Exception):
    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("authentication rate limit exceeded")
        self.retry_after_seconds = retry_after_seconds


class SlidingWindowRateLimiter:
    def __init__(self, *, attempts: int, window_seconds: int) -> None:
        if attempts < 1 or window_seconds < 1:
            raise ValueError("rate-limit settings must be positive")
        self._attempts = attempts
        self._window_seconds = window_seconds
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def hit(self, key: str) -> None:
        now = time.monotonic()
        window_start = now - self._window_seconds
        with self._lock:
            events = self._events[key]
            while events and events[0] <= window_start:
                events.popleft()
            if len(events) >= self._attempts:
                retry_after = max(1, math.ceil(events[0] + self._window_seconds - now))
                raise RateLimitExceeded(retry_after)
            events.append(now)
