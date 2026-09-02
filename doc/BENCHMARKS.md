# Benchmarks

Measurements and reproduction steps moved out of the README so the package page stays about the API. Numbers are from the machine and date stated below and are not updated automatically.

## Performance Snapshot

These local measurements were taken on 2026-07-05 on Windows x64, Intel Core
i3-1215U (6 cores, 8 logical processors), Dart 3.6.2, Node 24.14.1, Java
25.0.2, Go 1.26.4, OpenJPEG 2.5.4 built from `referencias/openjpeg` with CMake
4.3.3, Ninja 1.13.2, and GCC 16.1.0 from `C:\w64devkit`.

The Dart, JAI ImageIO, and Go rows are in-process API benchmarks. The JAI row is
the original Java reference this port is based on, built from
`referencias/jai-imageio-jpeg2000` and measured through its ImageIO SPI. The
OpenJPEG row uses the `opj_compress`/`opj_decompress` command line tools, so
process startup and file I/O are included and dominate this tiny 64x64 fixture.
Lower is better.

| Codec/runtime | Execution model | Gray encode PGM->J2K | Gray decode J2K | RGB/RGBA encode | RGB/RGBA decode | Notes |
|---|---|---:|---:|---:|---:|---|
| Dart VM JIT | in-process | 2772.2 us/op | 4733.0 us/op | 3850.8 us/op | 9863.6 us/op | `dart run`, 64x64 PGM/PPM, 80 iterations |
| Dart AOT exe | in-process | 2525.4 us/op | 5137.8 us/op | 6168.0 us/op | 12435.5 us/op | `dart compile exe` |
| Dart JavaScript `-O2` | Node 24 | 7900.0 us/op | 3762.5 us/op | 17075.0 us/op | 8400.0 us/op | `dart compile js -O2` |
| Dart WasmGC | Node 24 | 5046.7 us/op | 6768.2 us/op | 10024.4 us/op | 12250.3 us/op | `dart compile wasm` |
| JAI ImageIO JJ2000 | in-process | 5132.3 us/op | 4194.1 us/op | 9415.7 us/op | 7263.0 us/op | Original Java port reference; ImageIO SPI, fixed 512 MB heap |
| Go reference | in-process | 395.9 us/op | 1126.0 us/op | 819.7 us/op | 3271.2 us/op | `referencias/go-jpeg2000`; color case is RGBA |
| OpenJPEG C | CLI end-to-end | 11773.4 us/op | 12484.6 us/op | 12991.8 us/op | 15697.9 us/op | Native tools; includes startup and filesystem I/O |

### Optimization Targets

The first performance target is the original JAI ImageIO/JJ2000 Java reference.
On the Dart VM JIT, this port is already faster than JAI for lossless encoding,
but decoding still needs work:

| Target | Current Dart VM status |
|---|---:|
| Match JAI gray encode | Dart is about 1.85x faster |
| Match JAI RGB encode | Dart is about 2.44x faster |
| Match JAI gray decode | Dart is about 1.13x slower; needs roughly 11% less time |
| Match JAI RGB decode | Dart is about 1.36x slower; needs roughly 26% less time |

The longer-term target is the Go reference implementation. Against that row,
the Dart VM still needs a much larger gain:

| Target | Current Dart VM gap |
|---|---:|
| Match Go gray encode | Dart is about 7.0x slower |
| Match Go gray decode | Dart is about 4.2x slower |
| Match Go RGB encode | Dart is about 4.7x slower |
| Match Go RGB decode | Dart is about 3.0x slower |

In practical terms, the VM target after parity with JAI is a 4x to 5x average
speedup, with the worst current path near 7x. The first places to optimize are
RGB decode/component conversion/writer buffering, MQ and entropy decoder hot
loops, and allocation reuse in code-block and wavelet buffers. JavaScript and
Wasm should be treated as a separate browser optimization pass after the VM hot
paths are cleaner.

Reproduce the Dart rows with:

```bash
dart run benchmark/codec_benchmark.dart --size=64 --iterations=80 --warmup=8
dart compile exe benchmark/codec_benchmark.dart -o build/codec_benchmark.exe
build/codec_benchmark.exe --size=64 --iterations=80 --warmup=8
dart compile js -O2 --define=jpeg2000.benchmark.size=64 --define=jpeg2000.benchmark.iterations=80 --define=jpeg2000.benchmark.warmup=8 -o build/codec_benchmark.js benchmark/codec_benchmark.dart
node build/codec_benchmark.js
dart compile wasm --define=jpeg2000.benchmark.size=64 --define=jpeg2000.benchmark.iterations=80 --define=jpeg2000.benchmark.warmup=8 -o build/codec_benchmark.wasm benchmark/codec_benchmark.dart
node benchmark/run_wasm_benchmark.mjs build/codec_benchmark.mjs build/codec_benchmark.wasm
```

Reproduce the JAI ImageIO row on Windows PowerShell:

```powershell
C:\maven-mvnd-1.0.6\bin\mvnd.exe -f referencias\jai-imageio-jpeg2000\pom.xml '-DincludeScope=runtime' '-DoutputDirectory=C:\MyDartProjects\jpeg2000\build\jai-imageio-deps' dependency:copy-dependencies

$sources = Get-ChildItem referencias\jai-imageio-jpeg2000\src\main\java -Recurse -Filter *.java | ForEach-Object { $_.FullName }
$sources | Set-Content $env:TEMP\jai-imageio-jpeg2000-sources.txt
javac --release 8 -encoding UTF-8 -cp build\jai-imageio-deps\jai-imageio-core-1.4.0.jar -d build\jai-imageio-jpeg2000-classes "@$env:TEMP\jai-imageio-jpeg2000-sources.txt"
Copy-Item referencias\jai-imageio-jpeg2000\src\main\resources\* build\jai-imageio-jpeg2000-classes -Recurse -Force
jar cf build\jai-imageio-jpeg2000-local.jar -C build\jai-imageio-jpeg2000-classes .

javac --release 8 -encoding UTF-8 -cp "build\jai-imageio-jpeg2000-local.jar;build\jai-imageio-deps\jai-imageio-core-1.4.0.jar" -d build\java-benchmark benchmark\JaiImageioBenchmark.java
java '-Djava.awt.headless=true' -Xms512m -Xmx512m -cp "build\java-benchmark;build\jai-imageio-jpeg2000-local.jar;build\jai-imageio-deps\jai-imageio-core-1.4.0.jar" JaiImageioBenchmark --size=64 --iterations=200 --warmup=20
```

The JAI ImageIO POM still targets Java 6, which current JDKs reject, so the
commands above use `mvnd` to resolve dependencies and `javac --release 8` to
compile the local reference source. JDeli remains a correctness reference for
bit-exact fixture checks, but it is not included in this table because the
checked local JDeli CLI does not accept PGM/PPM input directly.

## Performance Roadmap

- Reduce allocations in code-blocks, wavelet buffers, color conversion, and
  writers by reusing `TypedData` across blocks.
- Profile and optimize MQ coder/decoder and entropy coder/decoder hot loops on
  the Dart VM and generated JavaScript.
- Expand automated benchmarks with larger fixture sets and a browser timing
  harness for Chrome.
- Evaluate tile/component parallelism with isolates on the VM and Web Workers
  in browsers.
- Implement true incremental reads for large inputs with configurable cache
  policies per platform.
- Expand the encoder to PGX, multiple independent input components, tile-parts,
  and packed packet headers.

