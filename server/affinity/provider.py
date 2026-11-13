"""Shared bounded, stateless Responses transport; never exposes upstream details."""
import json
import urllib.request


class ProviderError(Exception):
    """Sanitized upstream failure, without input, response bodies, or credentials."""


def request_json(api_key, payload, transport=None):
    request = urllib.request.Request(
        'https://api.openai.com/v1/responses', data=json.dumps(payload).encode(),
        headers={'Authorization': 'Bearer ' + api_key, 'Content-Type': 'application/json'}, method='POST')
    try:
        with (transport or urllib.request.urlopen)(request, timeout=20) as response:
            raw = response.read(65537)
        if len(raw) > 65536:
            raise ValueError()
        result = json.loads(raw)
        if not isinstance(result, dict) or result.get('status') != 'completed':
            raise ValueError()
        texts = []
        for item in result.get('output', []):
            if not isinstance(item, dict):
                raise ValueError()
            for content in item.get('content', []):
                if content.get('type') == 'refusal':
                    raise ValueError()
                if content.get('type') == 'output_text':
                    texts.append(content.get('text'))
        if len(texts) != 1:
            raise ValueError()
        value = json.loads(texts[0])
        if not isinstance(value, dict):
            raise ValueError()
        return value
    except Exception:
        raise ProviderError('provider_unavailable') from None
