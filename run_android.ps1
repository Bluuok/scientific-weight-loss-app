param([ValidateSet('build','run','test','analyze')][string]$Action='build')
$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
$env:PUB_CACHE=Join-Path $PSScriptRoot '.tools/pub-cache'
$env:ANDROID_HOME=Join-Path $PSScriptRoot '.tools/android-sdk'
$env:ANDROID_USER_HOME=Join-Path $PSScriptRoot '.tools/android-home'
$env:GRADLE_USER_HOME=Join-Path $PSScriptRoot '.tools/gradle'
$env:FLUTTER_SUPPRESS_ANALYTICS='true'
if (Test-Path 'C:/Program Files/Java/jdk-21') {$env:JAVA_HOME='C:/Program Files/Java/jdk-21'}
$flutter=Join-Path $PSScriptRoot '.tools/flutter/bin/flutter.bat'
if (!(Test-Path $flutter)) {throw 'Install Flutter 3.44.6 under .tools/flutter (see .fvmrc).'}
switch($Action){
 'build' {& $flutter build apk --debug --flavor develop}
 'run' {& $flutter run --flavor develop}
 'test' {& $flutter test test/features/meal_planner}
 'analyze' {& $flutter analyze}
}
exit $LASTEXITCODE
