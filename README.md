# jpeg2000

[![Dart CI](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/jpeg2000/actions/workflows/dart.yml)

Port em Dart puro do codec JPEG 2000/JJ2000, com decoder JP2/J2K, encoder
básico e testes de regressão bit-exatos contra fixtures versionados no próprio
repositório.

## Estado Atual

- Decoder JP2/J2K com parsing de codestream, entropy decode, ROI de-scaling,
  dequantização, inverse wavelet, RCT/ICT inverso e pipeline de cor JP2.
- Encoder com entrada PPM P6 e PGM P5, saída codestream J2K e wrapper JP2
  opcional.
- Fixtures consolidados em `test/fixtures`; os testes dependem apenas de
  arquivos versionados no repositório.
- Cobertura de CI para Dart VM e Chrome.
- Abstrações de plataforma usam export condicional e `package:web` para o lado
  browser. A CLI e o pipeline alto nível por arquivo ainda são VM-only porque
  usam filesystem.

## Instalação

Como o pacote ainda não é publicado no pub.dev:

```yaml
dependencies:
  jpeg2000:
    git:
      url: https://github.com/insinfo/jpeg2000.git
```

Depois:

```bash
dart pub get
```

## Uso Pela CLI

Decodificar JP2/J2K para PPM, PGM, PGX ou BMP:

```bash
dart run scripts/decode.dart -i input.jp2 -o output.ppm
dart run scripts/decode.dart -i input.j2k -o output.bmp
```

Codificar PPM/PGM para J2K lossless:

```bash
dart run scripts/encode.dart -i input.ppm -o output.j2k -lossless on
dart run scripts/encode.dart -i input.pgm -o output.j2k -lossless on
```

Codificar com wrapper JP2:

```bash
dart run scripts/encode.dart -i input.ppm -o output.jp2 -lossless on -file_format on
```

Codificar com taxa alvo:

```bash
dart run scripts/encode.dart -i input.ppm -o output.j2k -rate 1.0
```

## Uso Programático

A facade pública do pacote ainda será estabilizada. Hoje, para uso interno ou
experimental em Dart VM, use os mesmos blocos que alimentam as CLIs:

```dart
import 'package:jpeg2000/src/j2k/decoder/decoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';

void main() {
  final params = ParameterList(Decoder.buildDefaultParameterList())
    ..put('i', 'input.jp2')
    ..put('o', 'output.ppm')
    ..put('rate', '-1');

  final decoder = Decoder(params)..run();
  if (decoder.exitCode != 0) {
    throw StateError('Decoder failed with exit code ${decoder.exitCode}');
  }
}
```

Encoder:

```dart
import 'package:jpeg2000/src/j2k/encoder/encoder.dart';
import 'package:jpeg2000/src/j2k/util/ParameterList.dart';

void main() {
  final params = ParameterList(Encoder.buildDefaultParameterList())
    ..put('i', 'input.ppm')
    ..put('o', 'output.j2k')
    ..put('lossless', 'on');

  final encoder = Encoder(params)..run();
  if (encoder.exitCode != 0) {
    throw StateError('Encoder failed with exit code ${encoder.exitCode}');
  }
}
```

## Testes

```bash
dart analyze --fatal-infos
dart test
dart test -p chrome
```

Os fixtures ficam em:

- `test/fixtures/test_images`: imagens sintéticas, JP2/J2K e referências PPM.
- `test/fixtures/j2k_tests`: subconjunto de conformance e referências
  bit-exatas.
- `test/fixtures/*.json`: fixtures pequenos para entropy/MQ/paridade.

## CI

O workflow `.github/workflows/dart.yml` roda em cada push e pull request:

- `dart pub get`
- `dart format --output=none --set-exit-if-changed lib test scripts`
- `dart analyze --fatal-infos`
- `dart test`
- `dart test -p chrome`

## TODO De Performance E Web

- Criar uma facade pública estável para decodificar/codificar a partir de bytes,
  sem depender de paths ou `dart:io`.
- Adicionar API async/browser para carregar bytes via `package:web`, mantendo a
  camada síncrona interna de seek quando necessário.
- Reduzir alocações em code-blocks, buffers de wavelet, conversão de cor e
  writers, reaproveitando `TypedData` entre blocos.
- Medir e otimizar hot loops do MQ coder/decoder e entropy coder/decoder no VM
  e no JavaScript gerado.
- Criar benchmark automatizado para VM, Chrome e compilação JS minificada.
- Avaliar execução paralela por tile/componente com isolates no VM e Web
  Workers no browser.
- Implementar leitura incremental real para entradas grandes, com política de
  cache configurável por plataforma.
- Expandir o encoder para PGX, múltiplos componentes de entrada, tile-parts e
  packed packet headers.
