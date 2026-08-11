#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/.work"
DIST_DIR="$ROOT_DIR/dist"
ORIGINAL_AAR="$ROOT_DIR/original/tv-recyclerview-3.0.0-original.aar"
PATCHED_AAR="$DIST_DIR/tv-recyclerview-3.0.0-patched.aar"
CFR_JAR="$WORK_DIR/cfr.jar"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-34}"

rm -rf "$WORK_DIR" "$DIST_DIR"
mkdir -p "$WORK_DIR" "$DIST_DIR"

if [ ! -f "$ORIGINAL_AAR" ]; then
  echo "Missing original aar: $ORIGINAL_AAR" >&2
  exit 1
fi

cd "$WORK_DIR"
cp "$ORIGINAL_AAR" original.aar
unzip -q original.aar -d aar
mkdir classes
cd classes
jar xf ../aar/classes.jar
cd "$WORK_DIR"

if [ ! -f "$CFR_JAR" ]; then
  curl -L --fail -o "$CFR_JAR" https://repo1.maven.org/maven2/org/benf/cfr/0.152/cfr-0.152.jar
fi

mkdir -p decompiled
java -jar "$CFR_JAR" \
  classes/com/owen/tvrecyclerview/widget/TvRecyclerView.class \
  --outputdir decompiled >/dev/null

PATCHED_JAVA="decompiled/com/owen/tvrecyclerview/widget/TvRecyclerView.java"
if [ ! -f "$PATCHED_JAVA" ]; then
  echo "Failed to decompile TvRecyclerView.java" >&2
  exit 1
fi

PATCHED_JAVA="$PATCHED_JAVA" python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ['PATCHED_JAVA'])
text = path.read_text(encoding='utf-8')
needle = "public int getLastVisibleAndFocusablePosition()"
start = text.find(needle)
if start == -1:
    raise SystemExit("method not found")
brace = text.find('{', start)
if brace == -1:
    raise SystemExit("method body start not found")

depth = 0
end = None
for idx in range(brace, len(text)):
    ch = text[idx]
    if ch == '{':
        depth += 1
    elif ch == '}':
        depth -= 1
        if depth == 0:
            end = idx
            break
if end is None:
    raise SystemExit("method body end not found")

replacement = '''public int getLastVisibleAndFocusablePosition() {
        RecyclerView.LayoutManager lm = this.getLayoutManager();
        if (lm == null) {
            return -1;
        }
        int n = this.getFirstVisiblePosition();
        int n2 = this.getLastVisiblePosition();
        while (n2 >= n) {
            View view = lm.findViewByPosition(n2);
            if (view != null && view.isFocusable()) {
                return n2;
            }
            --n2;
        }
        return -1;
    }'''

text = text[:start] + replacement + text[end+1:]
path.write_text(text, encoding='utf-8')
PY

if [ -z "${ANDROID_HOME:-}" ]; then
  echo "ANDROID_HOME is not set" >&2
  exit 1
fi
ANDROID_JAR="$ANDROID_HOME/platforms/android-${ANDROID_PLATFORM}/android.jar"
if [ ! -f "$ANDROID_JAR" ]; then
  echo "Missing android.jar: $ANDROID_JAR" >&2
  exit 1
fi

mkdir -p deps extracted generated/com/owen/tvrecyclerview
cp "$ROOT_DIR/original/recyclerview-1.3.2.aar" deps/recyclerview.aar
cp "$ROOT_DIR/original/legacy-support-v4-1.0.0.aar" deps/legacy-support-v4.aar
cp "$ROOT_DIR/original/vlayout-1.2.37.aar" deps/vlayout.aar
cp "$ROOT_DIR/original/core-1.13.0.aar" deps/core.aar

for dep in recyclerview legacy-support-v4 vlayout core; do
  mkdir -p "extracted/$dep"
  unzip -q "deps/$dep.aar" -d "extracted/$dep"
  cp "extracted/$dep/classes.jar" "deps/$dep.jar"
done

cat > generated/com/owen/tvrecyclerview/R.java <<'EOF'
package com.owen.tvrecyclerview;

public final class R {
    public static final class styleable {
        public static final int[] TvRecyclerView = new int[5];
        public static final int TvRecyclerView_tv_layoutManager = 0;
        public static final int TvRecyclerView_selectedItemisCentered = 1;
        public static final int TvRecyclerView_selectedItemOffsetStart = 2;
        public static final int TvRecyclerView_selectedItemOffsetEnd = 3;
        public static final int TvRecyclerView_android_orientation = 4;
    }
}
EOF

mkdir -p patched-classes
javac \
  -encoding UTF-8 \
  -source 8 -target 8 \
  -cp "$ANDROID_JAR:$WORK_DIR/aar/classes.jar:$WORK_DIR/deps/recyclerview.jar:$WORK_DIR/deps/legacy-support-v4.jar:$WORK_DIR/deps/vlayout.jar:$WORK_DIR/deps/core.jar" \
  -d patched-classes \
  generated/com/owen/tvrecyclerview/R.java \
  "$PATCHED_JAVA"

cd patched-classes
PATCH_CLASSES=$(find com/owen/tvrecyclerview/widget -maxdepth 1 -type f -name 'TvRecyclerView*.class' | sort)
if [ -z "$PATCH_CLASSES" ]; then
  echo "No patched TvRecyclerView classes generated" >&2
  exit 1
fi
cd "$WORK_DIR"

mkdir replace-jar
cd replace-jar
jar xf ../aar/classes.jar
find com/owen/tvrecyclerview/widget -maxdepth 1 -type f -name 'TvRecyclerView*.class' -delete
cp -R ../patched-classes/com ./
jar cf ../aar/classes.jar .
cd "$WORK_DIR"

cd aar
zip -qr "$PATCHED_AAR" .
cd "$ROOT_DIR"

echo "Patched aar created: $PATCHED_AAR"
