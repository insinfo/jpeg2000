import com.github.jaiimageio.jpeg2000.J2KImageWriteParam;
import com.github.jaiimageio.jpeg2000.impl.J2KImageReaderSpi;
import com.github.jaiimageio.jpeg2000.impl.J2KImageWriterSpi;

import java.awt.image.BufferedImage;
import java.awt.image.WritableRaster;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.Iterator;
import java.util.Locale;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriter;
import javax.imageio.spi.IIORegistry;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.ImageOutputStream;

public final class JaiImageioBenchmark {
  private JaiImageioBenchmark() {}

  public static void main(String[] args) throws Exception {
    Locale.setDefault(Locale.ROOT);
    BenchmarkOptions options = BenchmarkOptions.parse(args);
    registerJpeg2000Spi();

    BufferedImage gray = grayImage(options.size);
    BufferedImage rgb = rgbImage(options.size);

    System.out.println(
        "benchmark size="
            + options.size
            + " iterations="
            + options.iterations
            + " warmup="
            + options.warmup);

    byte[] grayCodestream =
        time("encode gray image -> J2K", options, () -> encode(gray));
    time("decode gray J2K", options, () -> decode(grayCodestream));

    byte[] rgbCodestream =
        time("encode RGB image -> J2K", options, () -> encode(rgb));
    time("decode RGB J2K", options, () -> decode(rgbCodestream));

    System.out.println("gray bytes=" + grayCodestream.length);
    System.out.println("rgb bytes=" + rgbCodestream.length);
  }

  private static void registerJpeg2000Spi() {
    IIORegistry registry = IIORegistry.getDefaultInstance();
    registry.registerServiceProvider(new J2KImageReaderSpi());
    registry.registerServiceProvider(new J2KImageWriterSpi());
  }

  private static byte[] encode(BufferedImage image) throws Exception {
    Iterator<ImageWriter> writers = ImageIO.getImageWritersByFormatName("jpeg2000");
    if (!writers.hasNext()) {
      throw new IllegalStateException("JAI ImageIO JPEG 2000 writer is not registered");
    }

    ImageWriter writer = writers.next();
    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    try (ImageOutputStream output = ImageIO.createImageOutputStream(bytes)) {
      J2KImageWriteParam params = (J2KImageWriteParam) writer.getDefaultWriteParam();
      params.setLossless(true);
      params.setWriteCodeStreamOnly(true);
      writer.setOutput(output);
      writer.write(null, new IIOImage(image, null, null), params);
    } finally {
      writer.dispose();
    }
    return bytes.toByteArray();
  }

  private static BufferedImage decode(byte[] codestream) throws Exception {
    Iterator<ImageReader> readers = ImageIO.getImageReadersByFormatName("jpeg2000");
    if (!readers.hasNext()) {
      throw new IllegalStateException("JAI ImageIO JPEG 2000 reader is not registered");
    }

    ImageReader reader = readers.next();
    try (ImageInputStream input =
        ImageIO.createImageInputStream(new ByteArrayInputStream(codestream))) {
      reader.setInput(input, false, false);
      return reader.read(0);
    } finally {
      reader.dispose();
    }
  }

  private static BufferedImage grayImage(int size) {
    BufferedImage image = new BufferedImage(size, size, BufferedImage.TYPE_BYTE_GRAY);
    WritableRaster raster = image.getRaster();
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        raster.setSample(x, y, 0, (x * 17 + y * 11) & 0xff);
      }
    }
    return image;
  }

  private static BufferedImage rgbImage(int size) {
    BufferedImage image = new BufferedImage(size, size, BufferedImage.TYPE_INT_RGB);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        int i = y * size + x;
        int red = (i * 13) & 0xff;
        int green = (255 - i * 7) & 0xff;
        int blue = (32 + i * 5) & 0xff;
        image.setRGB(x, y, (red << 16) | (green << 8) | blue);
      }
    }
    return image;
  }

  private static <T> T time(String label, BenchmarkOptions options, ThrowingSupplier<T> run)
      throws Exception {
    T result = null;
    for (int i = 0; i < options.warmup; i++) {
      result = run.get();
    }

    long start = System.nanoTime();
    for (int i = 0; i < options.iterations; i++) {
      result = run.get();
    }
    long elapsed = System.nanoTime() - start;
    double averageMicros = elapsed / 1000.0 / options.iterations;
    System.out.printf(Locale.ROOT, "%s: %.1f us/op%n", label, averageMicros);
    return result;
  }

  private interface ThrowingSupplier<T> {
    T get() throws Exception;
  }

  private static final class BenchmarkOptions {
    private final int size;
    private final int iterations;
    private final int warmup;

    private BenchmarkOptions(int size, int iterations, int warmup) {
      this.size = size;
      this.iterations = iterations;
      this.warmup = warmup;
    }

    private static BenchmarkOptions parse(String[] args) {
      int size = 64;
      int iterations = 80;
      int warmup = 8;

      for (String arg : args) {
        if (arg.startsWith("--size=")) {
          size = positiveInt(arg, "--size=");
        } else if (arg.startsWith("--iterations=")) {
          iterations = positiveInt(arg, "--iterations=");
        } else if (arg.startsWith("--warmup=")) {
          warmup = nonNegativeInt(arg, "--warmup=");
        }
      }

      return new BenchmarkOptions(size, iterations, warmup);
    }

    private static int positiveInt(String arg, String prefix) {
      int value = nonNegativeInt(arg, prefix);
      if (value <= 0) {
        throw new IllegalArgumentException(prefix + " must be positive");
      }
      return value;
    }

    private static int nonNegativeInt(String arg, String prefix) {
      return Integer.parseInt(arg.substring(prefix.length()));
    }
  }
}
