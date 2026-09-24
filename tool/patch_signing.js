// Run by .github/workflows/build-apk.yml's "Configure release signing" step,
// after android/key.properties has been written. Wires a "release"
// signingConfig into the freshly-generated android/app/build.gradle(.kts)
// so `flutter build apk|appbundle --release` produces a properly signed
// artifact instead of falling back to the debug key.
const fs = require('fs');

const ktsPath = 'android/app/build.gradle.kts';
const groovyPath = 'android/app/build.gradle';
const isKts = fs.existsSync(ktsPath);
const file = isKts ? ktsPath : groovyPath;
let content = fs.readFileSync(file, 'utf8');

if (isKts) {
  content = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + content;
  const block = [
    'val keystoreProperties = Properties()',
    'val keystorePropertiesFile = rootProject.file("key.properties")',
    'if (keystorePropertiesFile.exists()) {',
    '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))',
    '}',
    '',
    'android {',
    '    signingConfigs {',
    '        create("release") {',
    '            keyAlias = keystoreProperties.getProperty("keyAlias")',
    '            keyPassword = keystoreProperties.getProperty("keyPassword")',
    '            storeFile = file(keystoreProperties.getProperty("storeFile"))',
    '            storePassword = keystoreProperties.getProperty("storePassword")',
    '        }',
    '    }',
  ].join('\n');
  content = content.replace('android {', block);
  content = content.replace(
    /signingConfig[^\n]*debug[^\n]*/,
    'signingConfig = signingConfigs.getByName("release")',
  );
} else {
  const block = [
    'def keystorePropertiesFile = rootProject.file("key.properties")',
    'def keystoreProperties = new Properties()',
    'if (keystorePropertiesFile.exists()) {',
    '    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))',
    '}',
    '',
    'android {',
    '    signingConfigs {',
    '        release {',
    '            keyAlias keystoreProperties.getProperty("keyAlias")',
    '            keyPassword keystoreProperties.getProperty("keyPassword")',
    '            storeFile file(keystoreProperties.getProperty("storeFile"))',
    '            storePassword keystoreProperties.getProperty("storePassword")',
    '        }',
    '    }',
  ].join('\n');
  content = content.replace('android {', block);
  content = content.replace(
    /signingConfig[^\n]*debug[^\n]*/,
    'signingConfig signingConfigs.release',
  );
}

fs.writeFileSync(file, content);
console.log('Patched', file, 'for release signing');
