"""Integracja z Ollama GLM-OCR — ekstrakcja tekstu z obrazów."""

from __future__ import annotations

import asyncio
import base64
import logging
from io import BytesIO
from typing import Any

import httpx
from PIL import Image

from worker.config import worker_settings

logger = logging.getLogger(__name__)

_MAX_RETRIES = 2
_RETRY_DELAY = 3.0
_TIMEOUT_PER_PAGE = 120.0
_MAX_IMAGE_SIZE = 1600


def preprocess_image(image_base64: str, max_size: int = _MAX_IMAGE_SIZE) -> str:
    """Skaluj obraz do max 1600px po dluższym boku, JPEG q85."""
    img_bytes = base64.b64decode(image_base64)
    img = Image.open(BytesIO(img_bytes))

    if max(img.size) > max_size:
        img.thumbnail((max_size, max_size), Image.LANCZOS)

    buffer = BytesIO()
    img.save(buffer, format="JPEG", quality=85)
    return base64.b64encode(buffer.getvalue()).decode()


class OllamaOCR:
    """Klient Ollama GLM-OCR do rozpoznawania tekstu z obrazów."""

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None

    async def _get_client(self) -> httpx.AsyncClient:
        """Lazy-init httpx klienta z odpowiednim timeoutem."""
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                base_url=worker_settings.ollama_url,
                timeout=httpx.Timeout(_TIMEOUT_PER_PAGE, connect=10.0),
            )
        return self._client

    async def close(self) -> None:
        """Zamknij httpx klienta."""
        if self._client is not None and not self._client.is_closed:
            await self._client.aclose()
            self._client = None

    async def process(self, image_base64: str) -> str:
        """Wyślij obraz do Ollama i zwróć rozpoznany tekst."""
        processed = preprocess_image(image_base64)

        payload: dict[str, Any] = {
            "model": worker_settings.ollama_model,
            "messages": [
                {
                    "role": "user",
                    "content": "OCR",
                    "images": [processed],
                }
            ],
            "stream": False,
        }

        last_error: Exception | None = None
        for attempt in range(1, _MAX_RETRIES + 1):
            try:
                client = await self._get_client()
                resp = await client.post("/api/chat", json=payload)
                resp.raise_for_status()
                data = resp.json()
                text: str = data.get("message", {}).get("content", "")
                return text

            except (httpx.ConnectError, httpx.ConnectTimeout) as exc:
                last_error = exc
                logger.warning(
                    "Ollama connection error (próba %d/%d): %s — retry za %.0fs",
                    attempt,
                    _MAX_RETRIES,
                    exc,
                    _RETRY_DELAY,
                )
                await self.close()
                if attempt < _MAX_RETRIES:
                    await asyncio.sleep(_RETRY_DELAY)

            except httpx.TimeoutException as exc:
                raise RuntimeError(
                    f"Ollama timeout ({_TIMEOUT_PER_PAGE}s): {exc}"
                ) from exc

            except httpx.HTTPStatusError as exc:
                raise RuntimeError(
                    f"Ollama HTTP {exc.response.status_code}: {exc.response.text[:200]}"
                ) from exc

        raise RuntimeError(
            f"Ollama niedostępna po {_MAX_RETRIES} próbach: {last_error}"
        )


# ── Globalny singleton ─────────────────────────────────────────────
