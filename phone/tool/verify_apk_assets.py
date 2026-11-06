"""빌드한 Android APK의 생물 데이터가 원본과 같은지 검사한다."""
from pathlib import Path
from zipfile import ZipFile

phone = Path(__file__).resolve().parents[1]
apk = phone / 'build/app/outputs/flutter-apk/app-debug.apk'
source = phone.parent / 'data/species.json'
asset = 'assets/flutter_assets/assets/data/species.json'
with ZipFile(apk) as archive:
    if asset not in archive.namelist():
        raise SystemExit(f'FAIL: APK에 생물 데이터가 없습니다: {asset}')
    if archive.read(asset) != source.read_bytes():
        raise SystemExit('FAIL: APK 생물 데이터가 data/species.json 원본과 다릅니다')
print('PASS: APK 생물 데이터 포함 및 원본 일치')
