# Test data for JJ2000 validation

Este diretório contém vetores de teste pequenos para validar o decoder/encoder JJ2000 em Dart e Java.

Estrutura proposta:

- `synthetic/`
  - Vetores sintéticos pequenos (ex.: `rainbowbars`, gradientes, checkerboard), em BMP/PGM/PPM + codestreams `.j2k`/`.jp2` e arquivos de referência decodificados (`reference.pgm`/`reference.ppm`).
- `conformance_subset/`
  - Subconjunto reduzido de arquivos de conformidade, derivados de suites como OpenJPEG/OpenHTJ2K, respeitando licenças e mantendo apenas o mínimo necessário.
- `pdf/`
  - PDFs pequenos com imagens JPEG 2000 embutidas para testes de integração via `pdfbox_dart`.

Cada caso de teste deve ficar em um subdiretório próprio contendo:

- Arquivo(s) de entrada (ex.: `input.bmp`, `input.pgm` ou `input.ppm`).
- Codestream(s) gerados (`*.j2k`, `*.jp2`).
- Saída(s) de referência (`reference.pgm`, `reference.ppm`) geradas por um decoder de referência (ex.: OpenJPEG).
- `meta.json` com metadados (largura, altura, bit depth, componentes, cores, se é lossless/lossy, tolerâncias de comparação, etc.).

A geração desses arquivos deve ser feita com scripts em `scripts/` (a definir), para garantir reprodutibilidade.
