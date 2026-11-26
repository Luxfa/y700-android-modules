#!/usr/bin/env bash
# 生成 + 编译 y700_icharger（javac -> d8 -> jar）
set -e
cd "$(dirname "$0")"
SDK="D:/Android/Sdk"
AJAR="$SDK/platforms/android-36/android.jar"
D8="$SDK/build-tools/36.0.0/lib/d8.jar"
[ -f "$AJAR" ] || { echo "缺 android.jar: $AJAR" >&2; exit 1; }

python3 gen.py
rm -rf out classes
mkdir -p out classes
javac -nowarn -source 8 -target 8 -encoding UTF-8 -bootclasspath "$AJAR" -d classes src/com/y700/icharger/Main.java
java -cp "$D8" com.android.tools.r8.D8 --release --min-api 33 --lib "$AJAR" --output out classes/com/y700/icharger/*.class
python3 - <<'PY'
import io, zipfile
d = io.open('out/classes.dex', 'rb').read()
with zipfile.ZipFile('y700_icharger.jar', 'w') as z:
    z.writestr('classes.dex', d)
print('y700_icharger.jar', len(d), 'bytes dex')
PY
ls -l y700_icharger.jar
