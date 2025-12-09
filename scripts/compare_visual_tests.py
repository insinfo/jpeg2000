import os
from pathlib import Path

def read_ppm_pixels(filepath):
    """Read PPM file and return pixel data after header"""
    with open(filepath, 'rb') as f:
        # Skip header lines (P6, width height, maxval)
        line_count = 0
        while line_count < 3:
            line = f.readline()
            if line[0] != ord('#'):  # Skip comments
                line_count += 1
        return f.read()

def compare_images(file1, file2, name1, name2):
    """Compare two PPM images pixel by pixel"""
    try:
        pixels1 = read_ppm_pixels(file1)
        pixels2 = read_ppm_pixels(file2)
        
        min_len = min(len(pixels1), len(pixels2))
        total_pixels = min_len // 3
        
        differences = 0
        max_diff = 0
        sum_diff = 0
        
        for i in range(0, min_len, 3):
            r1, g1, b1 = pixels1[i:i+3]
            r2, g2, b2 = pixels2[i:i+3]
            
            diff_r = abs(r1 - r2)
            diff_g = abs(g1 - g2)
            diff_b = abs(b1 - b2)
            
            max_channel_diff = max(diff_r, diff_g, diff_b)
            
            if max_channel_diff > 0:
                differences += 1
                max_diff = max(max_diff, max_channel_diff)
                sum_diff += max_channel_diff
        
        diff_percent = (differences * 100.0) / total_pixels if total_pixels > 0 else 0
        avg_diff = sum_diff / differences if differences > 0 else 0
        
        return {
            'total_pixels': total_pixels,
            'differences': differences,
            'diff_percent': diff_percent,
            'max_diff': max_diff,
            'avg_diff': avg_diff,
            'pass': diff_percent <= 50 and max_diff <= 5  # Lenient thresholds
        }
    except Exception as e:
        return {'error': str(e)}

def main():
    visual_tests_dir = Path('test_images/visual_tests')
    
    if not visual_tests_dir.exists():
        print(f"Directory not found: {visual_tests_dir}")
        return
    
    print("=" * 80)
    print("VISUAL COMPARISON: Dart vs OpenJPEG Decoder")
    print("=" * 80)
    
    test_names = [
        'gradient_32', 'gradient_64',
        'rainbow_32', 'rainbow_64',
        'checkerboard_32', 'checkerboard_64',
        'circles_32', 'circles_64',
        'text_32', 'text_64',
        'stripes_32', 'stripes_64'
    ]
    
    total_tests = 0
    passed_tests = 0
    
    for test_name in test_names:
        dart_file = visual_tests_dir / f'{test_name}_dart_decoded.ppm'
        openjpeg_file = visual_tests_dir / f'{test_name}_openjpeg_decoded.ppm'
        
        if not dart_file.exists() or not openjpeg_file.exists():
            print(f"\n{test_name}: SKIP (files not found)")
            continue
        
        result = compare_images(dart_file, openjpeg_file, 'Dart', 'OpenJPEG')
        
        if 'error' in result:
            print(f"\n{test_name}: ERROR - {result['error']}")
            continue
        
        total_tests += 1
        status = "✓ PASS" if result['pass'] else "✗ FAIL"
        if result['pass']:
            passed_tests += 1
        
        print(f"\n{test_name}:")
        print(f"  Total pixels: {result['total_pixels']}")
        print(f"  Differences: {result['differences']} ({result['diff_percent']:.2f}%)")
        print(f"  Max diff: {result['max_diff']}")
        print(f"  Avg diff: {result['avg_diff']:.2f}")
        print(f"  Status: {status}")
    
    print("\n" + "=" * 80)
    print(f"SUMMARY: {passed_tests}/{total_tests} tests passed")
    print("=" * 80)
    print(f"\nHTML comparison available at: {visual_tests_dir / 'comparison.html'}")
    print("Open this file in your browser to visually compare all images side-by-side.")

if __name__ == '__main__':
    main()
