import pathlib

root = pathlib.Path('app/android/app/src/main')

# ---- AndroidManifest ----
m = root / 'AndroidManifest.xml'
s = m.read_text()

s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

perms = '''
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
'''

service = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
'''

s = s.replace('<application', '<application android:requestLegacyExternalStorage="true"', 1)
s = s.replace('<application', perms + '\n    <application', 1)
s = s.replace('</application>', service + '    </application>', 1)
m.write_text(s)

# ---- MainActivity ----
for f in list(root.rglob('MainActivity.kt')) + list(root.rglob('MainActivity.java')):
    f.unlink()
kt = next(root.rglob('kotlin'), None) or (root / 'kotlin')
target = root / 'kotlin' / 'com' / 'example' / 'quran_player'
target.mkdir(parents=True, exist_ok=True)
(target / 'MainActivity.kt').write_text('''package com.example.quran_player

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
''')
print('patched OK')
