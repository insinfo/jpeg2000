# Investigação: bugs de decodificação no port Dart do JJ2000

Documento de trabalho — atualizado conforme a investigação avança.
Data de início: 2026-07-04
**Status: CONCLUÍDO — todos os bugs de decodificação corrigidos; decodificação
bit-exata com as referências (ver "Validação final" abaixo).**

## Sintoma

O decoder Dart (`lib/src`) produz imagens distorcidas para a maioria dos arquivos
de teste, enquanto os 263 testes unitários passam (eles cobrem kernels isolados,
não o pipeline completo — os testes de conformance só verificam que a decodificação
"não lança erro", sem validar pixels).

## Reprodução histórica

Esses sintomas agora estão cobertos por testes de regressão versionados no
repositório, principalmente `test/decoder_debug_findings_regression_test.dart`
e `test/conformance_subset_test.dart`. Os scripts temporários de comparação e
dump usados durante a investigação foram removidos depois que os fixtures
bit-exatos foram consolidados em `test/fixtures`.

## Resultados por imagem (comparação pixel a pixel vs referência JJ2000 Java)

| Imagem | Parâmetros (COD/QCD) | Resultado |
|---|---|---|
| `barras_rgb.jp2` | 32x32, 4 comps, **MCT=0**, 5x3 reversível | **PERFEITA** |
| `solid_blue_jj2000.j2k` | 256x256, MCT=1, 9x7 irrev., só DC | quase perfeita (diff máx 1) |
| `gradient_horizontal_jj2000.j2k` | 256x256, MCT=1, 9x7 irrev., 4 layers | QUEBRADA (diff máx 229) |
| `checkerboard_jj2000.j2k` | MCT=1, 9x7 | QUEBRADA (diff máx 147, igual nos 3 canais) |
| `circles_jj2000.j2k` | MCT=1, 9x7 | QUEBRADA (diff máx 255) |
| `noise_pattern_jj2000.j2k` | MCT=1, 9x7 | QUEBRADA (diff máx 255) |
| `file1.jp2` | 768x512, MCT=1, **5x3 reversível**, 1 layer | QUEBRADA (estrutura visível + ruído forte) |
| `relax.jp2` | 400x300, MCT=1, 5x3 reversível, 12 layers | MUITO QUEBRADA (magenta + ruído) |
| `icon32.jp2` | 32x32, MCT=1, 5x3 reversível | QUEBRADA (sai azul sólido) |

## Conclusões parciais

1. **O conteúdo DC (subband LL do nível mais baixo) decodifica quase certo** —
   `solid_blue` fica com diff máx 1 (arredondamento). A estrutura grossa de
   `file1` é visível sob o ruído.
2. **Os coeficientes de detalhe (HL/LH/HH) chegam corrompidos** em qualquer
   imagem com conteúdo espacial — tanto no caminho 5x3 int quanto no 9x7 float.
3. Em `checkerboard`/`rainbow_stripes` (conteúdo cinza) o erro é idêntico nos 3
   canais RGB → o erro vem do componente Y antes da transformada inversa de
   componentes (MCT), não da MCT em si.
4. `InvWTFull.dart` foi comparado linha a linha com `InvWTFull.java` — está
   fiel (orquestração da árvore, paridade ulcx/ulcy, offsets, cópia de
   code-blocks). O bug provavelmente está a montante: EntropyDecoder /
   Dequantizer / BitstreamReader (truncation points, msbSkipped) — ou em
   utilidades de bits de 32 bits usadas por eles.

## Estratégia

Depuração diferencial contra a referência Java original do porte. Essa cópia
foi usada somente durante a investigação; os testes atuais dependem apenas dos
fixtures versionados em `test/fixtures`.

1. ✅ Compilada a subárvore `jj2000` da referência standalone
   (165 classes, precisou de stubs para `I18N`, `ImageUtil`, `J2KImageWriter`
   e exclusão de `FileFormatReader`/`fileformat/writer` que dependem do
   jai-imageio-core).
2. ⏳ Escrever driver Java que monta o pipeline igual ao `J2KReadState`:
   `IISRandomAccessIO → HeaderDecoder → FileBitstreamReaderAgent →
   EntropyDecoder → ROIDeScaler → Dequantizer → InverseWT → ImgDataConverter →
   InvCompTransf` e faz dump por estágio:
   - A: coeficientes de cada code-block após entropy decode
   - B: após dequantizer
   - C: componente inteiro após inverse WT
   - D: após inverse MCT
3. ⏳ Driver Dart equivalente com o mesmo formato de dump.
4. ⏳ Diff dos dumps para `file1.jp2` → primeiro estágio divergente = local do bug.

## Depuração diferencial (file1.jp2)

Harness temporário construído:
- Java: driver de dump compilado contra a referência.
- Dart: driver equivalente de dump por estágio.
- Estágios: `cblk` (bytes comprimidos por code-block), `entropy`, `dequant`,
  `invwt`, `mct`. Formato de linha idêntico → diff textual.

Resultados:

| Estágio | Java vs Dart |
|---|---|
| `cblk` (dados comprimidos + skipMSBP + trunc points) | **0/309 blocos diferem — IDÊNTICOS** |
| `entropy` (coeficientes decodificados) | **309/309 blocos diferem** — até o bit de sinal diverge |

→ **O bug está DENTRO do entropy decoder** (`StdEntropyDecoder` / `MQDecoder` /
`ByteInputBuffer` / `ByteToBitInput`), não no PktDecoder/BitstreamReader.
A divergência começa cedo (afeta sinal e magnitudes), em todos os code-blocks,
inclusive o LL r=0.

Observação: os testes de fixture de entropy do Dart passam, mas é preciso
verificar se os fixtures foram gerados pelo próprio Dart (auto-referenciais)
em vez de virem do Java.

## Suspeitas anotadas (a confirmar)

- `InvCompTransfImgDataSrc` (Dart) é uma reescrita, não um port 1:1. Constantes
  do ICT inverso: `_ictBlueCbFactor = 1.7720907830451322` e
  `_ictBlueCrFactor = 0.00006723594218332702` — o padrão JJ2000 usa
  `B = Y + 1.772*Cb` (sem termo Cr). Efeito pequeno, mas é desvio da referência.
- `decoder.dart` usa `ImgDataConverter(invWT, invWT.getFixedPoint(0))` onde o
  Java usa `new ImgDataConverter(invWT, 0)`.

## Bugs encontrados e CORRIGIDOS

### Bug 1 — `_sigProgPass` (StdEntropyDecoder.dart): metade inferior da coluna
aninhada dentro do `if` de skip da metade superior

O Java processa a metade inferior de cada coluna do stripe SEMPRE (após o `if`
da metade superior). O Dart só a processava quando a metade superior não era
pulável → símbolos deixavam de ser decodificados → dessincronização do MQ.

### Bug 2 — `_sigProgPass`: perda das flags do estado da metade superior

Faltava `state[j] = csj;` antes de `j += sscanw` ao descer para a metade
inferior. As flags `VISITED_R1/R2` (e outras) acumuladas em `csj` eram
descartadas → o cleanup pass re-decodificava amostras já visitadas →
dessincronização.

### Bug 3 — `_sigProgPass`: guards `!causal` trocados

O Java aplica `if (!causal)` nos updates de vizinhos da metade SUPERIOR
(vizinhos do stripe anterior); o Dart tinha guards na metade INFERIOR (onde o
Java não tem) e não tinha na superior. Só afeta streams com
OPT_VERT_STR_CAUSAL, mas foi corrigido junto.

### Bug 4 — `_buildZcLutHh` (ZC_LUT_HH): regra do contexto 9 começava em h=0

Java: `for(i=1; i<16; i++) ZC_LUT_HH[(i<<4)|twoBits[j]] = 9;`
Dart tinha `h = 0`, o que sobrescrevia as entradas "2 diagonais significativos,
nenhum horiz/vert" (contexto 8) com contexto 9 → todos os code-blocks HH
decodificavam com contextos errados. Explica por que somente s=3 divergia após
os fixes 1–2.

### Bug 5 — `InvCompTransfImgDataSrc.getNomRangeBits` propagava os depths
"misturados" do RCT (9 bits) em vez dos originais

O Java `InvCompTransf.getNomRangeBits(c)` retorna `utdepth[c]` (depths originais
do SIZ), pois após a transformada inversa as amostras voltam ao range original.
A reescrita Dart herdava do adapter e devolvia o depth misturado do dequantizer
(9 para as crominâncias do RCT). Consequência: o writer calculava
`maxValue = 511`, o clamp em 255 nunca disparava e a escrita no `Uint8List`
fazia **wraparound** (overshoots tipo 260 viravam 4) → chuviscos e texto
vermelho em `relax.jp2`. Fix: novo parâmetro `originalBitDepths` +
override de `getNomRangeBits`.

### Bug 6 — `_applyICT` reescrito para semântica Java

A reescrita Dart do ICT inverso: (a) usava constantes erradas
(`0.344136/0.714136/1.7720907830451322` + um termo `BlueCr` inexistente no
Java); (b) produzia saída float, deixando o arredondamento para o conversor
seguinte. O Java usa `1.402f, 0.34413f, 0.71414f, 1.772f` e produz INT com
`(int)(x + 0.5f)` em aritmética float32. Reimplementado com emulação de
float32 (`_asFloat32`) — o caminho lossy 9x7 passou de diff ±1 sistemático
para **0** (2 amostras ±1 restantes em toda a suíte, 1 ulp do filtro wavelet
em double vs float32 — irrelevante).

### Bug 7 — typo na matriz do `MatrixBasedTransformTosRGB`

`matrix[M12]` usava `SRGB11 * dfPCS11`; o Java original usa
`SRGB11 * dfPCS12`.

### Bug 8 (comportamental) — perfil ICC degenerado em `relax.jp2`

O perfil ICC embutido em `relax.jp2` tem colorants degenerados
(rXYZ=(0,0,0), gXYZ=(-32768,0,0), bXYZ=(0,0,0) — verificado por parse
independente em Python). Aplicá-lo fielmente (como o JJ2000 original faria)
produz imagem magenta saturada. O jai-imageio (referência do port) **não
aplica** ICC aos pixels; o JDeli também ignora esse perfil. Adicionado guard
em `ICCProfiler.createInstance`: se a matriz de colorants for singular, loga
warning e retorna o source sem transformar.

## Validação final

| Caso | Resultado |
|---|---|
| `file1.jp2` (5x3 lossless, RCT) | **bit-exato** vs jai-imageio oficial E JDeli (0/1.179.648 amostras) |
| `relax.jp2` (5x3, 12 layers, ICC) | **bit-exato** vs jai-imageio oficial (0/360.000) |
| `barras_rgb.jp2` (4 comps, sem MCT) | **bit-exato** vs jai-imageio oficial |
| 8 imagens `*_jj2000.j2k` (9x7 lossy, ICT) | **0 diffs** vs decode do JJ2000 Java (exceto 2 amostras ±1 em `circles`/`noise_pattern` — 1 ulp float) |
| 6 imagens `*_openjpeg.jp2` | **0 diffs** vs decode de referência |
| Suíte de testes (`dart test`) | **todos passam** |

Nota: o "quadrado preto" no canto superior esquerdo de `file1.jp2` **faz parte
da imagem original** (confirmado pelo usuário em visualizadores independentes e
pelo decode do JDeli/jai-imageio, ambos bit-exatos com o nosso).

Nota 2: três testes tiveram asserções atualizadas porque haviam sido calibrados
contra a saída do decoder ainda bugado (`decoder_integration_test`,
`decoder_reference_comparison_test`, testes de ICT que esperavam saída float).

## Ferramentas de depuração aposentadas

Os drivers de dump, comparação visual e geração auxiliar foram úteis para
localizar os bugs, mas foram removidos depois que os casos relevantes viraram
fixtures e testes automatizados no próprio repositório.

Concluído — todos os bugs de decodificação foram encontrados e corrigidos
O decoder Dart agora produz saída bit-exata (0 pixels diferentes) comparado com o jai-imageio oficial (via ImageIO) e com o JDeli. Sobre sua mensagem: sim, confirmado — o quadrado preto no canto de file1.jp2 faz parte da imagem original (JDeli e jai-imageio mostram o mesmo), e isso está registrado no DEBUG_FINDINGS.md.

Os bugs (todos em código portado, achados por comparação diferencial estágio-a-estágio com o Java)
StdEntropyDecoder._sigProgPass — metade inferior da coluna aninhada no if de skip da metade superior. O Java sempre processa a metade inferior do stripe; o Dart a pulava quando a superior era pulável → símbolos MQ deixavam de ser consumidos → dessincronização do bitstream (a causa principal da distorção).
_sigProgPass — faltava state[j] = csj antes de descer para a metade inferior. As flags VISITED_R1/R2 eram perdidas e o cleanup pass re-decodificava amostras já visitadas.
_sigProgPass — guards !causal trocados (estavam na metade inferior; o Java os tem na superior).
ZC_LUT_HH — loop do contexto 9 começava em h=0 em vez de h=1, sobrescrevendo as entradas de contexto 8. Por isso todos os code-blocks HH decodificavam errado.
InvCompTransfImgDataSrc.getNomRangeBits propagava o depth "misturado" do RCT (9 bits) em vez dos depths originais do SIZ como o Java — o clamp do writer virava 511 e valores com overshoot davam wraparound (texto vermelho/chuviscos no relax). Além disso o ICT inverso usava constantes erradas e saída float; reimplementei fiel ao Java (1.402f/0.34413f/0.71414f/1.772f, saída int com (int)(x+0.5f) em float32 emulado), e corrigi um typo na matriz ICC (dfPCS11→dfPCS12).
Também descobri que o perfil ICC dentro do relax.jp2 é degenerado (colorants zerados) — aplicá-lo fielmente produz magenta em qualquer implementação. Adicionei um guard que detecta perfil singular e pula a transformação ICC com warning (mesmo comportamento do jai-imageio/JDeli).

Validação
file1.jp2, relax.jp2, barras_rgb.jp2: 0 diferenças vs jai-imageio oficial (file1 também 0 vs JDeli).
8 imagens lossy 9x7 e 6 OpenJPEG: 0 diferenças vs decodes de referência (só 2 amostras ±1 em toda a suíte — 1 ulp de float32 vs double no filtro wavelet).
dart test: todos os testes passam (3 testes tiveram asserções corrigidas — estavam calibrados contra a saída do decoder bugado, ex.: esperar >3 valores únicos em barras R/G/B puras).
Ficou no projeto
DEBUG_FINDINGS.md — o histórico completo da investigação, cada bug com explicação, e a tabela de validação.
test/fixtures — fixtures bit-exatos e imagens de referência usados pelos testes de regressão.

Update Todos

Ligar factories: EntropyCoder.createInstance → StdEntropyCoder, PostCompRateAllocator.createInstance → EBCOTRateAllocator

Portar ForwCompTransf.dart (RCT/ICT direto) do Java

Portar Tiler.dart do Java

Criar classe Encoder principal (espelho do JJ2000 Encoder.java) + script encode.dart

Verificar/completar ImgReaderPPM e ImgReaderPGM

Validar round-trip lossless (PPM → j2k → decode == original) e vs decoder Java
