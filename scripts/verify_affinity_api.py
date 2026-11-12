"""Runs the Dart client against the real local Python service, with synthetic evaluation."""
import base64,importlib.util,io,os,subprocess,tempfile,threading,secrets,shutil
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
dart=os.environ.get('DART_BIN') or shutil.which('dart')
if not dart: raise SystemExit('Set DART_BIN or put the Flutter Dart executable on PATH.')
if not (root/'phone/.dart_tool/package_config.json').exists(): raise SystemExit('Run flutter pub get in phone/ first.')
spec=importlib.util.spec_from_file_location('affinity_demo',root/'server/affinity/app.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as directory:
 token=secrets.token_urlsafe(32)
 server=m.create_server(token,directory,evaluate=lambda text:'positive')
 thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
 image=io.BytesIO();Image.new('RGB',(2,2),'blue').save(image,'PNG')
 env=dict(os.environ,SMOKE_ROOM_TOKEN=token,SMOKE_IMAGE=base64.b64encode(image.getvalue()).decode())
 try:
  r=subprocess.run([dart,'--packages='+str(root/'phone/.dart_tool/package_config.json'),str(root/'phone/tool/affinity_api_smoke.dart'),f'http://127.0.0.1:{server.server_port}'],env=env,cwd=root/'phone',capture_output=True,text=True,timeout=45)
  print(r.stdout.strip());print(r.stderr.strip()) if r.stderr else None
  if r.returncode:raise SystemExit(r.returncode)
 finally:server.shutdown();server.server_close();thread.join()
