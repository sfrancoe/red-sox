#!/usr/bin/env python3
"""Loopback-only story preview/fixture server. No upstream requests or paid API calls."""
import argparse
import copy
import http.server
import json
from pathlib import Path
from urllib.parse import urlsplit
from story_content import CATALOG_LIMIT, decode, digest, encoded, entry_path, validate_tree


def preview_server(root, port=0, fixtures=False):
    original = validate_tree(root)
    paths = {entry_path(e): (root / entry_path(e)).read_bytes() for e in original['stories']}
    second = copy.deepcopy(original)
    if fixtures:
        first = next(e for e in original['stories'] if e['renderer'] == 'guess-reveal')
        story = json.loads(paths[entry_path(first)])
        story.update(id='fixture-second-story', title='Another story, same app', kicker='LOCAL TEST FIXTURE',
                     intro='This sample checks remote discovery. It is not a published baseball story.',
                     question='Which number is larger?', correctChoiceID='ball-a',
                     answerTitle='The same renderer, a new story.', answer='This entry arrived from the fixture catalog without changing the app binary.',
                     conclusion='Fixture only. Never publish this sample.')
        story['choices'] = [{'id': 'ball-a', 'label': 'A', 'value': '9', 'unit': 'units', 'detail': 'The larger number'},
                            {'id': 'ball-b', 'label': 'B', 'value': '3', 'unit': 'units', 'detail': 'The smaller number'}]
        story['stats'] = []; story['bars'] = []; story['passport'] = None
        payload = encoded(story)
        entry = {**first, 'id': story['id'], 'title': story['title'], 'revision': digest(payload), 'summary': story['intro'], 'fallback': story['answer']}
        paths[entry_path(entry)] = payload
        second.update(revision='fixture-second-catalog', stories=[entry] + original['stories'])
    variants = {}
    if fixtures:
        chart_entry = next((e for e in original['stories'] if e['renderer'] == 'chart-trajectory'), None)
        if chart_entry:
            for kind in ['line', 'bar']:
                story = json.loads(paths[entry_path(chart_entry)])
                story.update(id='fixture-chart-' + kind, title='Chart renderer fixture · ' + kind,
                             kicker='LOCAL RENDERER TEST', intro='Synthetic presentation check. Never publish this fixture.')
                story['chart']['kind'] = kind
                if kind == 'bar':
                    for beat in story['chart']['emphasis']: beat.pop('comparison', None)
                    for row in story['chart']['series']:
                        row['points'] = row['points'][::10] + [row['points'][-1]]
                payload = encoded(story)
                entry = {**chart_entry, 'id': story['id'], 'title': story['title'], 'revision': digest(payload)}
                paths[entry_path(entry)] = payload
                variants['chart-' + kind] = {**original, 'revision': 'fixture-chart-' + kind, 'stories': [entry] + original['stories']}
    state = {'mode': 'normal' , 'catalog': original, 'redirectHits': 0}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            path = urlsplit(self.path).path
            if fixtures and path.startswith('/__fixture/'):
                action = path.removeprefix('/__fixture/')
                if action in variants: state.update(mode='normal', catalog=variants[action])
                elif action == 'next': state.update(mode='normal', catalog=second)
                elif action == 'rollback': state.update(mode='normal', catalog=original)
                elif action == 'reset': state.update(mode='normal', catalog=original, redirectHits=0)
                elif action in ['offline', 'malformed', 'unsupported', 'payload-failure', 'redirect']: state['mode'] = action
                elif action == 'redirect-target': state['redirectHits'] += 1
                elif action != 'state': return self.send_error(404)
                return self.respond(encoded({'mode': state['mode'], 'revision': state['catalog']['revision'], 'redirectHits': state['redirectHits']}))
            prefix = next((p for p in ['/api/data/', '/data/'] if path.startswith(p)), None)
            if prefix is None: return self.send_error(404)
            content = path.removeprefix(prefix)
            if content != 'stories/catalog-v1.json' and content not in paths: return self.send_error(404)
            if state['mode'] == 'offline' or (state['mode'] == 'payload-failure' and content != 'stories/catalog-v1.json'):
                return self.send_error(503)
            if content == 'stories/catalog-v1.json':
                if state['mode'] == 'malformed': return self.respond(b'{"schemaVersion":')
                if state['mode'] == 'unsupported': return self.respond(encoded({**state['catalog'], 'schemaVersion': 2}))
                if state['mode'] == 'redirect':
                    self.send_response(302); self.send_header('Location', '/__fixture/redirect-target'); self.end_headers(); return
                return self.respond(encoded(state['catalog']))
            return self.respond(paths[content])

        def respond(self, body):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)

        def log_message(self, *_): pass

    return http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-root', type=Path, default=Path(__file__).resolve().parents[1] / 'data')
    parser.add_argument('--port', type=int, default=0)
    parser.add_argument('--ready-file', type=Path)
    parser.add_argument('--fixtures', action='store_true', help='Enable loopback-only fault/discovery/rollback controls')
    args = parser.parse_args()
    server = preview_server(args.data_root, args.port, args.fixtures)
    origin = f'http://127.0.0.1:{server.server_port}'
    if args.ready_file: args.ready_file.write_text(origin)
    print(f'Local preview: HUB_STORY_ROOT={origin}/data', flush=True)
    print('No upstream or production calls. Press Ctrl-C to stop.', flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
