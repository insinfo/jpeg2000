# Conformance Subset

This directory contains a small subset of JPEG 2000 conformance test files.

## Files

- `file1.jp2`: Small test image.
- `relax.jp2`: Image with color.
- `file1_reference.ppm`: jai-imageio-decoded RGB reference for pixel comparison.
- `relax_reference.ppm`: jai-imageio-decoded RGB reference for pixel comparison.

## Notes

Reference images were generated from the original Java baseline during the port
investigation and are committed here so `test/conformance_subset_test.dart`
does not depend on external reference checkouts.
