import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class LearningLauncherTest(unittest.TestCase):
    def test_check_validates_private_config_without_requesting_or_disclosing_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            launcher = root / 'scripts/run_learning_demo.py'
            shutil.copyfile(Path(__file__).resolve().parents[1] / launcher.name, launcher)
            env = {k: v for k, v in os.environ.items() if k != 'OPENAI_API_KEY'}
            missing = subprocess.run([sys.executable, str(launcher), '--check'], env=env,
                                     capture_output=True, text=True, timeout=5)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn('configuration is missing', missing.stderr)
            config = root / 'phone/config/learning-demo.local.json'
            config.parent.mkdir(parents=True)
            token = 'synthetic-private-token-' + 'a' * 32
            config.write_text(json.dumps({'ALLO_DEMO_TOKEN': token}))
            checked = subprocess.run([sys.executable, str(launcher), '--check'], env=env,
                                     capture_output=True, text=True, timeout=5)
            self.assertEqual(checked.returncode, 0, checked.stderr)
            self.assertIn('No provider call', checked.stdout)
            self.assertNotIn(token, checked.stdout + checked.stderr)
            config.write_text(json.dumps({'ALLO_DEMO_TOKEN': 'short'}))
            invalid = subprocess.run([sys.executable, str(launcher), '--check'], env=env,
                                     capture_output=True, text=True, timeout=5)
            self.assertNotEqual(invalid.returncode, 0)
            self.assertIn('Invalid private demo token', invalid.stderr)


if __name__ == '__main__':
    unittest.main()
