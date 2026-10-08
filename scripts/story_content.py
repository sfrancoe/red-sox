"""Versioned editorial story contract. Standard library only; never executes content."""
import hashlib
import json
import math
import re
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

CATALOG_LIMIT = 128 * 1024
PAYLOAD_LIMIT = 512 * 1024
SLUG = re.compile(r'[a-z0-9]+(?:-[a-z0-9]+)*\Z')
HASH = re.compile(r'[a-f0-9]{64}\Z')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(value, limit=2000):
    require(isinstance(value, str) and 0 < len(value) <= limit and not any(ord(c) < 32 and c not in '\n\t' for c in value), 'Invalid text')


def identifier(value):
    require(isinstance(value, str) and len(value) <= 80 and SLUG.fullmatch(value), 'Invalid identifier')


def timestamp(value):
    require(isinstance(value, str) and value.endswith('Z'), 'Expected UTC timestamp')
    datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ')


def integer(value, lower=0, upper=100000):
    require(type(value) is int and lower <= value <= upper, 'Invalid integer')


def unique(items):
    require(len({row['id'] for row in items}) == len(items), 'Duplicate identifiers')


def decode(data, limit):
    require(len(data) <= limit, 'Content exceeds size limit')
    def no_duplicates(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'Duplicate JSON key')
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=no_duplicates, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Non-finite number')))


def entry_path(entry):
    identifier(entry['id'])
    require(isinstance(entry['revision'], str) and HASH.fullmatch(entry['revision']), 'Invalid revision hash')
    return f"stories/{entry['id']}/{entry['revision']}.json"


def validate_entry(entry):
    entry_path(entry)
    for field, limit in [('title', 160), ('summary', 400), ('fallback', 2000)]:
        text(entry[field], limit)
    identifier(entry['renderer'])
    integer(entry['rendererVersion'], 1, 100)
    integer(entry['minimumRendererVersion'], 1, 100)
    timestamp(entry['publishedAt'])
    teams = entry['teamIDs']
    require(isinstance(teams, list) and len(teams) <= 30 and len(set(teams)) == len(teams), 'Invalid team list')
    for team in teams:
        integer(team, 1, 1000)


def validate_catalog(catalog):
    require(type(catalog['schemaVersion']) is int and catalog['schemaVersion'] == 1, 'Unsupported catalog schema')
    identifier(catalog['revision'])
    timestamp(catalog['publishedAt'])
    require(isinstance(catalog['stories'], list) and len(catalog['stories']) <= 120, 'Too many stories')
    unique(catalog['stories'])
    for entry in catalog['stories']:
        validate_entry(entry)
    return catalog


def validate_payload(payload, entry=None):
    require(type(payload['schemaVersion']) is int and payload['schemaVersion'] == 1, 'Unsupported story schema')
    identifier(payload['id'])
    require(payload['renderer'] == 'guess-reveal' and type(payload['rendererVersion']) is int and payload['rendererVersion'] == 1, 'Unsupported story renderer')
    for field, limit in [('title', 160), ('kicker', 160), ('intro', 2000), ('question', 300), ('answerTitle', 200), ('answer', 2000), ('conclusion', 2000)]:
        text(payload[field], limit)
    choices = payload['choices']
    require(2 <= len(choices) <= 4, 'Expected two to four choices')
    unique(choices)
    for choice in choices:
        identifier(choice['id'])
        for field in ['label', 'value', 'unit', 'detail']:
            text(choice[field], 300)
    require(payload['correctChoiceID'] in {c['id'] for c in choices}, 'Missing correct choice')
    require(len(payload['stats']) <= 6 and len(payload['bars']) <= 8, 'Too many chart values')
    for stat in payload['stats']:
        for field in ['label', 'value', 'note']:
            text(stat[field], 300)
    for bar in payload['bars']:
        text(bar['label'], 160)
        text(bar['unit'], 80)
        text(bar['detail'], 500)
        require(type(bar['value']) in [int, float] and math.isfinite(bar['value']) and 0 <= bar['value'] <= 100000, 'Invalid chart value')
    maximum = payload.get('barMaximum')
    if maximum is not None:
        require(type(maximum) in [int, float] and math.isfinite(maximum) and 1 <= maximum <= 100000 and all(b['value'] <= maximum for b in payload['bars']), 'Invalid chart maximum')
    passport = payload.get('passport')
    if passport is not None:
        text(passport['title'], 160)
        text(passport['intro'])
        require(1 <= len(passport['items']) <= 60, 'Invalid grid size')
        unique(passport['items'])
        for item in passport['items']:
            identifier(item['id'])
            for field in ['label', 'name', 'detail']:
                text(item[field], 1000)
            require(item['result'] in ['yes', 'no', 'unknown'], 'Invalid grid result')
    require(1 <= len(payload['methodology']) <= 12, 'Missing methodology')
    for paragraph in payload['methodology']:
        text(paragraph)
    require(1 <= len(payload['sources']) <= 12, 'Missing sources')
    unique(payload['sources'])
    for source in payload['sources']:
        identifier(source['id'])
        text(source['title'], 200)
        url = urlsplit(source['url'])
        require(url.scheme == 'https' and url.hostname and not url.username and not url.password and len(source['url']) <= 2000, 'Unsafe source URL')
        timestamp(source['retrievedAt'])
    if entry:
        require(payload['id'] == entry['id'] and payload['title'] == entry['title'], 'Story identity mismatch')
        require(payload['renderer'] == entry['renderer'] and payload['rendererVersion'] == entry['rendererVersion'], 'Renderer mismatch')
    return payload


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def validate_tree(root: Path):
    catalog = validate_catalog(decode((root / 'stories/catalog-v1.json').read_bytes(), CATALOG_LIMIT))
    for entry in catalog['stories']:
        data = (root / entry_path(entry)).read_bytes()
        require(digest(data) == entry['revision'], 'Payload hash mismatch')
        validate_payload(decode(data, PAYLOAD_LIMIT), entry)
    return catalog
