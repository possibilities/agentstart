"""Hermetic ownership and convergence tests for direct MCP delivery."""
import copy
import hashlib
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parent.parent


def module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    result = importlib.util.module_from_spec(spec)
    loader.exec_module(result)
    return result


provision = module('provision', ROOT/'scripts/install-mcp-gateway')
render = module('render', ROOT/'scripts/render-mcp-resources')


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))
    path.chmod(0o600)


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='agentstart-mcp-install-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)/'home'
        self.home.mkdir()
        self.resources = self.home/'.local/share/agentstart/resources/mcp-servers.json'
        save(self.resources, render.render(ROOT/'config/resources/mcp-servers.json', self.home))
        self.status = {'BackendState':'Running','Self':{'Online':True,'DNSName':'fixture.ts.net.'}}

    def prepare(self):
        with patch.object(provision, 'tail', return_value=self.status):
            provision.prepare(self.home)

    def test_renderer_expands_only_declared_home_without_startup_side_effects(self):
        result = json.loads(self.resources.read_text())['mcpServers']
        self.assertEqual(len(result), 19)
        self.assertEqual(result['agentnotify'], {'command': str(self.home/'.local/bin/agentnotify'), 'args': ['mcp']})
        self.assertEqual(result['agentdesk']['command'], str(self.home/'.local/bin/agentdesk'))
        self.assertEqual(result['shadcn'], {
            'command': str(self.home/'.local/bin/agentstart'), 'args': ['mcp', 'shadcn'],
        })
        self.assertEqual(result['gog_notimpossiblemike']['args'][1], 'notimpossiblemike@gmail.com')
        bad = self.home/'bad.json'
        save(bad, {'mcpServers':{'test':{'command':'${SECRET}', 'args':[]}}})
        with self.assertRaisesRegex(ValueError, 'unsupported template'):
            render.render(bad, self.home)

    def test_stable_private_credentials_and_new_toolset(self):
        self.prepare()
        base = self.home/'.config/agentstart'
        gateway = json.loads((base/'mcp-gateway.json').read_text())
        inventory = set(json.loads(self.resources.read_text())['mcpServers'])
        self.assertEqual(set(gateway['toolsets']['fleet']['tools']), inventory)
        self.assertEqual(set(gateway['toolsets']['grok']['tools']), {
            'agentboard', 'agentbrain', 'agentchats', 'agentsearch', 'agentwiki',
            'gog_mikebannister', 'gog_notimpossiblemike', 'shadcn', 'termctrl',
        })
        client = base/'mcp-clients/fleet.json'
        first = json.loads(client.read_text())
        digest = json.loads((base/'mcp-credentials/fleet.json').read_text())
        self.assertEqual(hashlib.sha256(first['token'].encode()).hexdigest(), digest['sha256'])
        self.assertEqual(client.stat().st_mode & 0o777, 0o600)
        grok = json.loads((base/'mcp-clients/grok.json').read_text())
        self.assertNotEqual(first['token'], grok['token'])
        self.assertEqual(grok['url'], 'https://fixture.ts.net/mcp/grok')
        self.prepare()
        self.assertEqual(json.loads(client.read_text()), first)
        config = json.loads((base/'mcp-gateway.json').read_text())
        config['toolsets']['reading'] = {'tools':{'agentbrain':['guide']}}
        save(base/'mcp-gateway.json', config)
        self.prepare()
        other = json.loads((base/'mcp-clients/reading.json').read_text())
        self.assertNotEqual(first['token'], other['token'])
        self.assertEqual(other['url'], 'https://fixture.ts.net/mcp/reading')
        self.assertEqual(json.loads(client.read_text()), first)
        # A rejected candidate does not rotate credentials or partly publish.
        config = json.loads((base/'mcp-gateway.json').read_text())
        config['port'] = 1
        save(base/'mcp-gateway.json', config)
        before = {p: p.read_bytes() for p in base.rglob('*.json')}
        with self.assertRaises(subprocess.CalledProcessError): self.prepare()
        self.assertEqual({p:p.read_bytes() for p in base.rglob('*.json')}, before)

    def test_foreign_or_linked_paths_are_refused(self):
        base = self.home/'.config/agentstart'
        base.mkdir(parents=True)
        elsewhere = self.home/'independent'
        elsewhere.mkdir()
        (base/'mcp-clients').symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'unsafe private path parent'): self.prepare()
        self.assertEqual(list(elsewhere.iterdir()), [])
        (base/'mcp-clients').unlink()
        save(base/'mcp-gateway.json', {'independent':True})
        with self.assertRaises(FileNotFoundError): self.prepare()
        self.assertEqual(json.loads((base/'mcp-gateway.json').read_text()), {'independent':True})

    def test_funnel_changes_only_its_handler_after_auth_checks(self):
        base = self.home/'.config/agentstart'
        save(base/'mcp-gateway.json', {'port':4790,'public_origin':'https://fixture.ts.net','toolsets':{'one':{},'two':{}}})
        original = {'TCP':{'443':{'HTTPS':True},'48410':{'HTTPS':True}},
                    'Web':{'fixture.ts.net:443':{'Handlers':{
                        '/':{'Proxy':'http://127.0.0.1:8787'},
                        '/mcp':{'Proxy':'http://127.0.0.1:4789/mcp'}}}},
                    'AllowFunnel':{'fixture.ts.net:443':True}}
        state = copy.deepcopy(original)
        calls = []
        def tail(*args):
            calls.append(args)
            if args == ('funnel','status','--json'): return copy.deepcopy(state)
            self.assertEqual(args, ('funnel','--yes','--bg','--set-path=/mcp','http://127.0.0.1:4790/mcp'))
            state['Web']['fixture.ts.net:443']['Handlers']['/mcp']={'Proxy':args[-1]}
            return ''
        checks = []
        def unauthorized(url, **_):
            checks.append(url)
            raise HTTPError(url, 401, 'Unauthorized', {'WWW-Authenticate':'Bearer'}, None)
        with patch.object(provision, 'tail', side_effect=tail), patch.object(provision, 'urlopen', side_effect=unauthorized):
            provision.expose(self.home)
            provision.expose(self.home)
            self.assertEqual(len([c for c in calls if '--set-path=/mcp' in c]), 1)
            self.assertEqual(set(checks), {'http://127.0.0.1:4790/mcp/one','http://127.0.0.1:4790/mcp/two'})
            state['Web']['fixture.ts.net:443']['Handlers']['/mcp']={'Proxy':'http://independent:8000'}
            before = copy.deepcopy(state)
            with self.assertRaisesRegex(ValueError, 'independently owned'): provision.expose(self.home)
            self.assertEqual(state, before)
        self.assertEqual(state['TCP'], original['TCP'])
        self.assertEqual(state['Web']['fixture.ts.net:443']['Handlers']['/'], original['Web']['fixture.ts.net:443']['Handlers']['/'])

if __name__ == '__main__':
    unittest.main()
