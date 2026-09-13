# Divergências deliberadas do JJ2000

Este pacote é um porte do JJ2000 e é bit-exato contra ele no subconjunto de conformidade
embutido. Onde o porte **difere de propósito**, a razão fica registrada aqui — para que
ninguém "conserte" de volta ao comportamento da referência achando que é regressão.

---

## 1. Geometria de componente em resolução reduzida

**O que a referência faz.** Em
`jj2000-5.1b2/src/jj2000/j2k/wavelet/synthesis/InvWTAdapter.java`, as consultas de geometria
respondem em duas unidades diferentes:

| Método | Nível usado |
|---|---|
| `getImgWidth()`, `getImgHeight()`, `getImgULX()`, `getImgULY()` | `reslvl` — a resolução **alvo** |
| `getTileCompWidth()`, `getTileCompHeight()`, `getCompImgWidth()`, `getCompImgHeight()`, `getCompULX()`, `getCompULY()` | `mressrc.getSynSubbandTree(t, c).resLvl` |

E a árvore de subbandas é construída em
`FileBitstreamReaderAgent.java` com `mdl[c]`, que vem de `decSpec.dls` — os **níveis de
decomposição declarados no codestream**, não a resolução pedida:

```java
mdl[c] = ((Integer) decSpec.dls.getTileCompVal(t, c)).intValue();
subbTrees[c] = new SubbandSyn(getTileCompWidth(t, c, mdl[c]), ...,  mdl[c], ...);
```

Logo os dois grupos divergem sempre que se pede resolução reduzida: a imagem encolhe e a
geometria de ladrilho e de componente não.

**Sintoma observável na própria referência.** Decodificando `file1.jp2` (768×512, 5 níveis)
com o JJ2000 compilado a partir do software de referência da ITU-T T.804:

```
java JJ2KDecoder -i file1.jp2 -o saida.ppm -res 0
    Reconstructing resolution 0 on 5 (24x16)
```

O cabeçalho PPM sai correto (`P6 24 16 255`), mas o arquivo tem 39 109 bytes quando
24 × 16 × 3 + cabeçalho são 1 165. A referência escreve mais amostras do que o próprio
cabeçalho declara.

**O que este pacote faz.** O nível correto para o componente `c` é
`resLevel - maxImgRes + resLvl(c)` — o mesmo limiar que `InvWTFull` já usa para decidir quais
subbandas sintetizar — e o tamanho sai da fórmula da T.800 B.5. Em resolução cheia o valor é
idêntico ao da referência, então o caminho normal não muda e a bit-exatidão se mantém.

**Corroboração independente.** O OpenJPEG, que não deriva do JJ2000 e implementa o mesmo
recurso, reduz a geometria de componente pelo mesmo fator da imagem
(`src/lib/openjp2/j2k.c`):

```c
l_img_comp->w = ceildivpow2(l_comp_x1, factor) - ceildivpow2(l_img_comp->x0, factor);
l_img_comp->h = ceildivpow2(l_comp_y1, factor) - ceildivpow2(l_img_comp->y0, factor);
```

`ceildivpow2(x, n)` é `ceil(x / 2^n)`, que é exatamente a divisão com teto da B.5. O JasPer
não serve de contraponto aqui: o decodificador dele não expõe redução de resolução nenhuma
(as opções são `maxlyrs`, `maxpkts`, `max_samples` e `debug`).

**Teste que trava isso:** `test/reduced_resolution_test.dart`. O caso decisivo são doze
ladrilhos de cor chapada, onde qualquer erro de posicionamento na grade reduzida apareceria
como diferença de cor; a diferença máxima é zero em todos os níveis.

---

## 2. Semântica da opção `resolution`

A documentação antiga dizia "número de níveis a descartar". O valor é o **nível a
reconstruir**, com `0` sendo o menor e o máximo sendo a resolução cheia, com clamp acima
disso. É a mesma convenção do `-res` do JJ2000; só o texto estava errado.

---

## Como reproduzir a comparação

O software de referência da ITU-T T.804 traz JJ2000, JasPer e OpenJPEG. O JJ2000 compila com
um JDK moderno sem alteração nenhuma:

```bash
cd Software/jj2000-5.1b2
find src -name '*.java' > sources.txt
javac -nowarn -encoding ISO-8859-1 -d classes @sources.txt
java -cp classes JJ2KDecoder -i entrada.jp2 -o saida.ppm -res 2
```
