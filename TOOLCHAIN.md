# Lifewave App — Toolchain (verified 2026-10-17)

Everything below was installed and smoke-tested end to end on this VM on
2026-10-17: `flutter analyze` clean, `flutter test` passed, and
`flutter build apk --debug` produced a working APK. Follow the env block
**verbatim** — the VM-specific quirks in it are load-bearing.

## Installed versions

| Component | Version | Location |
|---|---|---|
| Flutter | 3.24.5 (stable, framework rev dec2ee5c1f, engine a18df97ca5) | `~/workspace/toolchain/flutter/` |
| Dart | 3.5.4 (DevTools 2.37.3) | bundled with Flutter |
| JDK (JAVA_HOME) | Temurin 17.0.20.1+1 | `~/workspace/toolchain/jdk-17.0.20.1+1/` |
| Android cmdline-tools | 12.0 (11076708) | `~/workspace/toolchain/android-sdk/cmdline-tools/latest/` |
| Android SDK Platform | android-34, revision 3 | `~/workspace/toolchain/android-sdk/platforms/android-34/` |
| Android SDK Build-Tools | 34.0.0 (plus 33.0.1, auto-installed by AGP on first build) | `~/workspace/toolchain/android-sdk/build-tools/` |
| Android Platform-Tools | 37.0.1 (adb 1.0.41) | `~/workspace/toolchain/android-sdk/platform-tools/` |
| Gradle (project wrapper) | 8.3 (`gradle-8.3-all`, from the Flutter 3.24.5 template) | cached in the dedicated Gradle home below |
| Android Gradle Plugin | 8.1.0 (Flutter template default) | resolved into the dedicated Gradle home |
| Kotlin Android plugin | 1.8.22 (Flutter template default) | resolved into the dedicated Gradle home |
| Dedicated Gradle user home | — | `~/workspace/toolchain/gradle-user-home/` (gradle.properties + wrapper dists + caches) |

Project: `~/workspace/lifewave/app/` — `flutter create --org app.lifewave
--project-name lifewave_app --platforms=android,windows app`
Application ID / namespace: `app.lifewave.lifewave_app`

## Required environment (use verbatim for every build)

```bash
export JAVA_HOME=$HOME/workspace/toolchain/jdk-17.0.20.1+1
export ANDROID_SDK_ROOT=$HOME/workspace/toolchain/android-sdk
export PATH=$HOME/workspace/toolchain/flutter/bin:$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH
export GRADLE_USER_HOME=$HOME/workspace/toolchain/gradle-user-home
export JAVA_TOOL_OPTIONS="-Djava.net.preferIPv4Stack=true"
export GRADLE_OPTS="-Djava.net.preferIPv4Stack=true -Dhttp.proxyHost=hatch-egress-proxy -Dhttp.proxyPort=3128 -Dhttps.proxyHost=hatch-egress-proxy -Dhttps.proxyPort=3128"
export SDKMANAGER_OPTS="-Djava.net.preferIPv4Stack=true -Dhttps.proxyHost=hatch-egress-proxy -Dhttps.proxyPort=3128 -Dhttp.proxyHost=hatch-egress-proxy -Dhttp.proxyPort=3128"
flutter config --android-sdk $ANDROID_SDK_ROOT   # already set; harmless to repeat
```

## Reproduce: analyze / test / build

```bash
# (with the env block above exported)
cd ~/workspace/lifewave/app
flutter analyze        # template: "No issues found!"
flutter test           # template: "All tests passed!"
flutter build apk --debug
# -> build/app/outputs/flutter-apk/app-debug.apk  (83 MB, 2026-10-17 build)
```

sdkmanager (licenses / more packages), with the env block above:

```bash
yes | sdkmanager --sdk_root=$ANDROID_SDK_ROOT --licenses
sdkmanager --sdk_root=$ANDROID_SDK_ROOT --list_installed
sdkmanager --sdk_root=$ANDROID_SDK_ROOT "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

## VM quirks — do not skip these

1. **IPv4 stack flag is mandatory for Java networking.**
   Without `-Djava.net.preferIPv4Stack=true` at JVM *startup*, Java uses
   IPv4-mapped IPv6 sockets; this VM's egress gateway intercepts/resets
   those connections (symptoms: `NoSuchElementException` in
   `HttpURLConnection.doTunneling`, `SSLException: Unsupported or
   unrecognized SSL message`, or Gradle `Connection reset` on every
   repository). Setting it via `systemProp.*` in gradle.properties is too
   late for the Gradle daemon — that is why `JAVA_TOOL_OPTIONS` (read by
   every JVM at birth: wrapper, client, daemon, Kotlin daemon) **and**
   `GRADLE_OPTS` are both in the env block. `SDKMANAGER_OPTS` does the
   same job for sdkmanager.
2. **Proxy:** all Java downloads must go through
   `hatch-egress-proxy:3128` (no credentials needed from inside the VM;
   curl/python use the `*_proxy` env vars automatically, Java does not).
   The proxy props are in `GRADLE_OPTS` / `SDKMANAGER_OPTS` above and in
   `~/workspace/toolchain/gradle-user-home/gradle.properties`.
3. **Egress CA rotation (fixed 2026-10-17, may recur).**
   The proxy MITMs TLS with the "Hatch Sandbox Egress CA". On 2026-10-17
   the CA in the JDK/JBR cacerts was stale (SHA-256 `65:33:CB:EE:…`)
   vs. the system CA (SHA-256 `1B:5B:08:C7:52:22:AA:38:76:5A:45:B5:50:30:87:26:C5:AD:B2:99:13:20:CE:54:0F:7D:33:CC:33:BA:E9:61`),
   causing `PKIX path validation failed: signature check failed` on every
   Java HTTPS call. Fix (already applied to JDK 17, `jbr-21`, and
   `jbr-21-ipv4`; backups saved as `cacerts.bak-20261017` beside each
   keystore): delete alias `hatch-egress-ca` from cacerts
   (`keytool -delete -cacerts -storepass changeit -alias hatch-egress-ca`)
   and re-import `/etc/ssl/certs/hatch-egress-ca.pem`
   (`keytool -importcert -cacerts -storepass changeit -noprompt -alias hatch-egress-ca -file /etc/ssl/certs/hatch-egress-ca.pem`),
   verify the fingerprint matches `openssl x509 -in /etc/ssl/certs/hatch-egress-ca.pem -noout -fingerprint -sha256`,
   then stop all Gradle daemons so they reload the keystore.
   If Java PKIX errors return, suspect this first.
4. **Dedicated Gradle user home is required.**
   Do NOT use the shared `~/.gradle`: its gradle.properties sets
   `org.gradle.java.home` to the `jbr-21-ipv4` wrapper script, whose
   daemon reports `java.home=jbr-21` and fails Gradle 8.3's daemon
   context check ("newly created daemon process has a different context").
   `~/workspace/toolchain/gradle-user-home/gradle.properties` instead sets
   `org.gradle.java.home` to the real JDK 17 path, plus the proxy
   systemProps and `org.gradle.jvmargs` with the IPv4 flag.
   Note: gradle.properties precedence is per-property and confusing
   (user-home beat the project file for `org.gradle.java.home`;
   the project file beat user-home for `org.gradle.jvmargs`) — keep both
   files as they are; they are configured to work together.
   Also: Java ignores `$HOME` for Gradle's default user home (it uses the
   passwd entry, `/root`), another reason `GRADLE_USER_HOME` must be set
   explicitly.
5. **RAM: 7.7 GB, no swap.** `android/gradle.properties` lowers the
   template heap to `-Xmx2G` (from 4 G). A first-ever build with cold
   caches still got its daemon OOM-killed once while another project's
   4 GB daemon was running concurrently; with warm caches the debug
   build takes ~3 minutes. Avoid running two Gradle builds at once.
6. **Running as root:** Flutter prints "Woah! You appear to be trying to
   run flutter as root." — harmless on this VM.
7. `flutter doctor` expected non-Android complaints: no Chrome, no Linux
   desktop toolchain (clang/ninja/GTK), no Android Studio. Android
   toolchain shows ✓ with "All Android licenses accepted."

## First-install download sources (for a rebuild from scratch)

- Flutter: `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.24.5-stable.tar.xz`
  → extract to `~/workspace/toolchain/flutter/` (ignore tar
  "Cannot change ownership" warnings; extraction still completes).
- Cmdline tools: `https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip`
  → unzip, place contents at `~/workspace/toolchain/android-sdk/cmdline-tools/latest/`
  (`bin/sdkmanager` must be at that path), then accept licenses and
  install the three packages with the sdkmanager commands above.
- Never stage downloads under `/tmp` (wiped on VM restart).
