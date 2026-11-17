import functools
import http.server
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid


REPO = pathlib.Path(__file__).resolve().parents[2]


def run(*args, **options):
    return subprocess.run(args, cwd=REPO, check=True, text=True, **options)


def verify(framework, signer, binary, directory):
    requests = []
    info = plistlib.loads((REPO / "Scripts/Info.plist").read_bytes())
    seed = directory / "seed.b64"
    creation = directory / "CreateFixtureKey.swift"
    creation.write_text("""import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
print(key.publicKey.rawRepresentation.base64EncodedString())
try key.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
""")
    public_key = run("swift", creation, seed, capture_output=True).stdout.strip()

    class Handler(http.server.SimpleHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            super().do_GET()

        def log_message(self, format, *args):
            pass

    def app(location, bundle_id, feed_url, number):
        bundle = location / "KopyFixture.app"
        contents = bundle / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Frameworks").mkdir()
        shutil.copy2(binary, contents / "MacOS/Kopy")
        shutil.copytree(framework, contents / "Frameworks/Sparkle.framework", symlinks=True)
        metadata = dict(info, CFBundleIdentifier=bundle_id, CFBundleVersion=str(number),
                        CFBundleShortVersionString=f"0.{number}.0", CFBundleName="Kopy Fixture",
                        CFBundleDisplayName="Kopy Fixture", SUFeedURL=feed_url, SUPublicEDKey=public_key,
                        NSAppTransportSecurity={"NSAllowsLocalNetworking": True})
        (contents / "Info.plist").write_bytes(plistlib.dumps(metadata))
        run("codesign", "--force", "--sign", "-", bundle, capture_output=True)
        run("codesign", "--verify", "--deep", "--strict", bundle)
        return bundle

    server_factory = functools.partial(Handler, directory=str(directory))
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), server_factory) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        for group in ("off", "notify", "auto", "up-to-date", "reject-feed", "reject-archive"):
            location = directory / group
            bundle_id = f"com.kopy.updater-fixture.{group}.{uuid.uuid4().hex}"
            prefix = f"http://127.0.0.1:{server.server_port}/{group}"
            feed_url = f"{prefix}/appcast.xml"
            host = app(location / "installed", bundle_id, feed_url, 1)
            number = 1 if group == "up-to-date" else 2
            latest = app(location / "new", bundle_id, feed_url, number)
            archive = location / "update.zip"
            run("ditto", "-c", "-k", "--keepParent", latest, archive)
            attributes = run(signer, "--ed-key-file", seed, archive, capture_output=True).stdout.strip()
            feed = location / "appcast.xml"
            feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel><title>Kopy Fixture</title><link>{feed_url}</link>
    <item><title>Version 0.{number}.0</title><sparkle:version>{number}</sparkle:version>
      <sparkle:shortVersionString>0.{number}.0</sparkle:shortVersionString>
      <enclosure url="{prefix}/update.zip" type="application/octet-stream" {attributes}/>
    </item>
  </channel>
</rss>
''')
            run(signer, "--ed-key-file", seed, feed, capture_output=True)
            if group == "reject-feed":
                feed.write_text(feed.read_text().replace("Kopy Fixture", "Altered Fixture", 1))
            if group == "reject-archive":
                with archive.open("r+b") as file:
                    file.write(b"corrupt")

            start = len(requests)
            try:
                with subprocess.Popen([host / "Contents/MacOS/Kopy"], text=True,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      env=dict(os.environ, KOPY_UPDATE_TEST=group)) as probe:
                    try:
                        if group not in ("notify", "auto"):
                            time.sleep(1)
                            assert len(requests) == start, "Off fetched before the manual check"
                        output, _ = probe.communicate(timeout=40)
                    except BaseException:
                        probe.kill()
                        raise
                print(group, output.strip(), sep="\n", flush=True)
                assert probe.returncode == 0, output
                appcast_request, archive_request = f"/{group}/appcast.xml", f"/{group}/update.zip"
                expected = [appcast_request]
                if group == "notify":
                    expected.append(appcast_request)
                if group in ("off", "notify", "auto", "reject-archive"):
                    expected.append(archive_request)
                assert requests[start:] == expected, requests[start:]
                expected_state = ("upToDate" if group == "up-to-date" else
                                  "failed" if group.startswith("reject-") else 'ready(version: "0.2.0")')
                assert expected_state in output, output
                plist = host / "Contents/Info.plist"
                if group == "auto":
                    receipt = host.parent / "relaunched"
                    deadline = time.monotonic() + 15
                    while not receipt.exists() and time.monotonic() < deadline:
                        time.sleep(0.2)
                    assert receipt.exists(), "The installed application failed to relaunch"
                    assert plistlib.loads(plist.read_bytes())["CFBundleVersion"] == "2"
                    run("codesign", "--verify", "--deep", "--strict", host)
                else:
                    assert plistlib.loads(plist.read_bytes())["CFBundleVersion"] == "1"
            finally:
                subprocess.run(["defaults", "delete", bundle_id], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                shutil.rmtree(pathlib.Path.home() / "Library/Caches" / bundle_id, ignore_errors=True)
        server.shutdown()
    print("All six updater scenarios passed, including installation and relaunch.")


if __name__ == "__main__":
    binaries = pathlib.Path(run("swift", "build", "--show-bin-path", capture_output=True).stdout.strip())
    framework = binaries / "Sparkle.framework"
    signer = REPO / ".build/artifacts/sparkle/Sparkle/bin/sign_update"
    if not framework.is_dir() or not signer.is_file():
        raise SystemExit("Run swift build once before starting the updater integration test.")

    with tempfile.TemporaryDirectory(prefix="kopy-signed-update-test-") as path:
        directory = pathlib.Path(path)
        binary = directory / "Kopy"
        run("swiftc", "-parse-as-library", "-F", binaries, "-framework", "Sparkle",
            "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks",
            REPO / "Sources/KopyApp/Platform/KopyUpdater.swift", pathlib.Path(__file__).with_name("UpdaterProbe.swift"),
            "-o", binary)
        verify(framework, signer, binary, directory)
