"""Exercise real HTTP/stdio auth, isolation, filtering, fidelity and child cleanup."""
import asyncio
import copy
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import unittest

import httpx2 as httpx
from fastmcp import Client
from fastmcp.client.elicitation import ElicitResult
from gateway import build_gateway

FIXTURE = r'''
import json, os, sys
from pathlib import Path
Path(sys.argv[1], str(os.getpid())).touch()
count = 0
for line in sys.stdin:
    msg = json.loads(line)
    if 'id' not in msg: continue
    method, params = msg['method'], msg.get('params', {})
    if method == 'initialize':
        data = {'protocolVersion': params['protocolVersion'], 'capabilities': {'tools': {}, 'resources': {}, 'prompts': {}}, 'serverInfo': {'name': 'fixture', 'version': '1'}}
    elif method == 'tools/list':
        data = {'tools': [{'name': n, 'description': n, 'inputSchema': {'type': 'object', 'properties': {}}} for n in ['counter', 'private', 'failure', 'image', 'ask', 'stall']]}
    elif method == 'tools/call':
        name = params['name']
        count += 1
        data = {'content': [{'type': 'text', 'text': str(count)}], 'structuredContent': {'count': count, 'pid': os.getpid()}, 'isError': name == 'failure'}
        if name == 'ask':
            print(json.dumps({'jsonrpc':'2.0','id':1000,'method':'elicitation/create','params':{
                'mode':'form','message':'fixture approval','requestedSchema':{'type':'object','properties':{}}}}), flush=True)
            answer = json.loads(sys.stdin.readline())
            data['structuredContent']['action'] = answer.get('result',{}).get('action')
        if name == 'stall':
            cancel = json.loads(sys.stdin.readline())
            Path(sys.argv[1]).parent.joinpath('cancelled').write_text(cancel.get('method',''))
            data['isError'] = True
        if name == 'image':
            data['content'].append({'type': 'image', 'mimeType': 'image/png', 'data': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='})
    elif method == 'resources/list':
        data = {'resources': [{'name':'private', 'uri':'private://state'}]}
    elif method == 'resources/templates/list': data = {'resourceTemplates': []}
    elif method == 'prompts/list': data = {'prompts': [{'name':'private'}]}
    else: data = {}
    print(json.dumps({'jsonrpc':'2.0', 'id':msg['id'], 'result':data}), flush=True)
'''


def write_json(path, value):
    path.write_text(json.dumps(value))
    path.chmod(0o600)
    return str(path)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


class GatewayTest(unittest.IsolatedAsyncioTestCase):
    async def test_real_transports(self):
        with tempfile.TemporaryDirectory(prefix='agentstart-gateway-test-') as raw:
            root = Path(raw)
            fixture = root / 'fixture.py'
            fixture.write_text(FIXTURE)
            pids = root / 'pids'
            pids.mkdir()
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            resources = {'mcpServers': {'test': {'command': sys.executable, 'args': [str(fixture), str(pids)]}}}
            resources['mcpServers']['broken'] = {'command':sys.executable,'args':['-c','raise SystemExit(7)']}
            resource_path = write_json(root / 'resources.json', resources)
            tokens = {'one': 'one-' + 'a' * 43, 'two': 'two-' + 'b' * 43, 'broken': 'broken-' + 'c' * 43}
            config = {'version': 1, 'resources': resource_path, 'port': port,
                      'public_origin': 'https://fixture.ts.net', 'session_idle_seconds': 30, 'toolsets': {}}
            for name, token in tokens.items():
                credential = write_json(root / (name + '.json'), {'version': 1, 'sha256': hashlib.sha256(token.encode()).hexdigest()})
                config['toolsets'][name] = {'credential': credential, 'tools': {'test': ['counter', 'failure', 'image', 'ask', 'stall'] if name == 'one' else ['private']}}
            config['toolsets']['broken']['tools'] = {'test':['counter'],'broken':['*']}
            config_path = write_json(root / 'config.json', config)
            bad = copy.deepcopy(config)
            bad['toolsets']['two']['credential'] = bad['toolsets']['one']['credential']
            with self.assertRaisesRegex(ValueError, 'different credentials'):
                build_gateway(bad)
            bad = copy.deepcopy(config)
            bad['toolsets']['one']['tools'] = {'missing': ['counter']}
            with self.assertRaisesRegex(ValueError, 'invalid tool selection'):
                build_gateway(bad)
            log_path = root / 'gateway.log'
            with log_path.open('w') as log:
                process = subprocess.Popen([sys.executable, str(Path(__file__).with_name('gateway.py')), config_path], stdout=log, stderr=log)
                try:
                    base = f'http://127.0.0.1:{port}'
                    async with httpx.AsyncClient(timeout=2) as http:
                        for _ in range(100):
                            if process.poll() is not None:
                                self.fail(log_path.read_text())
                            try:
                                await http.get(base + '/mcp')
                                break
                            except httpx.ConnectError:
                                await asyncio.sleep(0.05)
                        for path in ['/mcp', '/mcp/unknown']:
                            self.assertEqual((await http.get(base + path)).status_code, 404)
                        for method in ['GET', 'POST', 'DELETE']:
                            for token in [None, 'wrong', tokens['two']]:
                                headers = {'Authorization': 'Bearer ' + token} if token else {}
                                response = await http.request(method, base + '/mcp/one', headers=headers)
                                self.assertEqual(response.status_code, 401, (method, response.text))
                                self.assertIn('Bearer', response.headers['www-authenticate'])
                        response = await http.get(base + '/mcp/one', headers={'Authorization': 'Bearer '+tokens['one'], 'Origin':'https://untrusted.example'})
                        self.assertEqual(response.status_code, 403)
                    self.assertEqual(list(pids.iterdir()), [], 'unauthorized requests started a backend')
                    asked, answered = asyncio.Event(), asyncio.Event()
                    async def decline(message, *_):
                        self.assertEqual(message, 'fixture approval')
                        asked.set()
                        await answered.wait()
                        return ElicitResult(action='decline')
                    async with Client(base + '/mcp/one', auth=tokens['one'], elicitation_handler=decline) as first:
                        self.assertEqual({tool.name for tool in await first.list_tools()}, {'test_counter', 'test_failure', 'test_image', 'test_ask', 'test_stall'})
                        one = await first.call_tool('test_counter', {})
                        two = await first.call_tool('test_counter', {})
                        self.assertEqual(one.structured_content['count'], 1)
                        self.assertEqual(two.structured_content['count'], 2)
                        self.assertEqual(one.structured_content['pid'], two.structured_content['pid'])
                        self.assertEqual(await first.list_resources(), [])
                        self.assertEqual(await first.list_prompts(), [])
                        denied = await first.call_tool('test_private', {}, raise_on_error=False)
                        self.assertTrue(denied.is_error)
                        native_error = await first.call_tool('test_failure', {}, raise_on_error=False)
                        self.assertTrue(native_error.is_error)
                        self.assertEqual(native_error.structured_content['count'], 3)
                        picture = await first.call_tool('test_image', {})
                        self.assertEqual(picture.content[1].type, 'image')
                        self.assertEqual(picture.content[1].mime_type, 'image/png')
                        pending = asyncio.create_task(first.call_tool('test_ask', {}))
                        await asyncio.wait_for(asked.wait(), 2)
                        concurrent = asyncio.create_task(first.list_tools())
                        await asyncio.sleep(0.03)
                        self.assertFalse(concurrent.done(), 'discovery crossed a pending callback')
                        answered.set()
                        decision = await asyncio.wait_for(pending, 2)
                        self.assertEqual(decision.structured_content['action'], 'decline')
                        await asyncio.wait_for(concurrent, 2)
                        with self.assertRaises(asyncio.TimeoutError):
                            await asyncio.wait_for(first.call_tool('test_stall', {}), 0.1)
                        # Cancellation releases the request lock and reaches stdio.
                        await asyncio.wait_for(first.call_tool('test_counter', {}), 2)
                        self.assertEqual((root/'cancelled').read_text(), 'notifications/cancelled')
                        async with Client(base + '/mcp/one', auth=tokens['one'], mode='legacy') as second:
                            fresh = await second.call_tool('test_counter', {})
                            self.assertEqual(fresh.structured_content['count'], 1)
                            self.assertNotEqual(fresh.structured_content['pid'], one.structured_content['pid'])
                        async with Client(base + '/mcp/two', auth=tokens['two'], mode='legacy') as other:
                            self.assertEqual([t.name for t in await other.list_tools()], ['test_private'])
                            self.assertTrue((await other.call_tool('test_counter', {}, raise_on_error=False)).is_error)
                    with self.assertRaises(Exception):
                        async with Client(base + '/mcp/broken', auth=tokens['broken']) as broken:
                            await broken.list_tools()
                    for _ in range(100):
                        if not any(alive(int(path.name)) for path in pids.iterdir()):
                            break
                        await asyncio.sleep(0.05)
                    self.assertFalse(any(alive(int(path.name)) for path in pids.iterdir()), 'session close leaked a stdio process')
                    # Server shutdown with a live client must reap its backend too.
                    async with Client(base + '/mcp/one', auth=tokens['one'], mode='legacy') as last:
                        await last.call_tool('test_counter', {})
                        process.send_signal(signal.SIGTERM)
                        await asyncio.to_thread(process.wait, 10)
                    # Uvicorn re-raises the original signal after graceful cleanup.
                    self.assertIn(process.returncode, [0, -signal.SIGTERM], log_path.read_text())
                    self.assertFalse(any(alive(int(path.name)) for path in pids.iterdir()), 'SIGTERM leaked a stdio process')
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try: process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                    for path in pids.iterdir():
                        if alive(int(path.name)):
                            os.kill(int(path.name), signal.SIGTERM)


if __name__ == '__main__':
    unittest.main()
