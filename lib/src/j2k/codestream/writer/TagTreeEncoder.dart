import '../../util/ArrayUtil.dart';
import 'BitOutputBuffer.dart';

/// This class implements the tag tree encoder. A tag tree codes a 2D matrix of
/// integer elements in an efficient way. The encoding procedure 'encode()'
/// codes information about a value of the matrix, given a threshold. The
/// procedure encodes the sufficient information to identify whether or not the
/// value is greater than or equal to the threshold.
///
/// The tag tree saves encoded information to a BitOutputBuffer.
///
/// A particular and useful property of tag trees is that it is possible to
/// change a value of the matrix, provided both new and old values of the
/// element are both greater than or equal to the largest threshold which has
/// yet been supplied to the coding procedure 'encode()'. This property can be
/// exploited through the 'setValue()' method.
///
/// This class allows saving the state of the tree at any point and
/// restoring it at a later time, by calling save() and restore().
///
/// A tag tree can also be reused, or restarted, if one of the reset()
/// methods is called.
///
/// The TagTreeDecoder class implements the tag tree decoder.
///
/// Tag trees that have one dimension, or both, as 0 are allowed for
/// convenience. Of course no values can be set or coded in such cases.
class TagTreeEncoder {
  /// The horizontal dimension of the base level
  late int w;

  /// The vertical dimensions of the base level
  late int h;

  /// The number of levels in the tag tree
  int lvls = 0;

  /// The tag tree values. The first index is the level, starting at level 0
  /// (leafs). The second index is the element within the level, in
  /// lexicographical order.
  late List<List<int>> treeV;

  /// The tag tree state. The first index is the level, starting at level 0
  /// (leafs). The second index is the element within the level, in
  /// lexicographical order.
  late List<List<int>> treeS;

  /// The saved tag tree values. The first index is the level, starting at
  /// level 0 (leafs). The second index is the element within the level, in
  /// lexicographical order.
  List<List<int>>? treeVbak;

  /// The saved tag tree state. The first index is the level, starting at
  /// level 0 (leafs). The second index is the element within the level, in
  /// lexicographical order.
  List<List<int>>? treeSbak;

  /// The saved state. If true the values and states of the tree have been
  /// saved since the creation or last reset.
  bool saved = false;

  /// Creates a tag tree encoder with 'w' elements along the horizontal
  /// dimension and 'h' elements along the vertical direction. The total
  /// number of elements is thus 'vdim' x 'hdim'.
  ///
  /// The values of all elements are initialized to Integer.MAX_VALUE.
  ///
  /// [h] The number of elements along the horizontal direction.
  ///
  /// [w] The number of elements along the vertical direction.
  ///
  /// [val] The values with which initialize the leafs of the tag tree.
  TagTreeEncoder(int h, int w, [List<int>? val]) {
    int k;
    // Check arguments
    if (w < 0 || h < 0) {
      throw ArgumentError();
    }
    if (val != null && val.length < w * h) {
      throw ArgumentError();
    }

    // Initialize elements
    _init(w, h);

    if (val == null) {
      // Set values to max
      for (k = treeV.length - 1; k >= 0; k--) {
        ArrayUtil.intArraySet(treeV[k], 2147483647); // Integer.MAX_VALUE
      }
    } else {
      // Update leaf values
      for (k = w * h - 1; k >= 0; k--) {
        treeV[0][k] = val[k];
      }
      // Calculate values at other levels
      _recalcTreeV();
    }
  }

  /// Returns the number of leafs along the horizontal direction.
  int getWidth() {
    return w;
  }

  /// Returns the number of leafs along the vertical direction.
  int getHeight() {
    return h;
  }

  /// Initializes the variables of this class, given the dimensions at the
  /// base level (leaf level). All the state ('treeS' array) and values
  /// ('treeV' array) are intialized to 0. This method is called by the
  /// constructors.
  ///
  /// [w] The number of elements along the vertical direction.
  ///
  /// [h] The number of elements along the horizontal direction.
  void _init(int w, int h) {
    int i;
    // Initialize dimensions
    this.w = w;
    this.h = h;
    // Calculate the number of levels
    if (w == 0 || h == 0) {
      lvls = 0;
    } else {
      lvls = 1;
      while (h != 1 || w != 1) {
        // Loop until we reach root
        w = (w + 1) >> 1;
        h = (h + 1) >> 1;
        lvls++;
      }
    }
    // Allocate tree values and states (no need to initialize to 0 since
    // it's the default)
    treeV = List.generate(lvls, (_) => []);
    treeS = List.generate(lvls, (_) => []);
    w = this.w;
    h = this.h;
    for (i = 0; i < lvls; i++) {
      treeV[i] = List.filled(h * w, 0);
      treeS[i] = List.filled(h * w, 0);
      w = (w + 1) >> 1;
      h = (h + 1) >> 1;
    }
  }

  /// Recalculates the values of the elements in the tag tree, in levels 1
  /// and up, based on the values of the leafs (level 0).
  void _recalcTreeV() {
    int m, n, bi, lw, tm1, tm2, lh, k;
    // Loop on all other levels, updating minimum
    for (k = 0; k < lvls - 1; k++) {
      // Visit all elements in level
      lw = (w + (1 << k) - 1) >> k;
      lh = (h + (1 << k) - 1) >> k;
      for (m = ((lh >> 1) << 1) - 2; m >= 0; m -= 2) {
        // All quads with 2 lines
        for (n = ((lw >> 1) << 1) - 2; n >= 0; n -= 2) {
          // All quads with 2 columns
          // Take minimum of 4 elements and put it in higher
          // level
          bi = m * lw + n;
          tm1 = (treeV[k][bi] < treeV[k][bi + 1])
              ? treeV[k][bi]
              : treeV[k][bi + 1];
          tm2 = (treeV[k][bi + lw] < treeV[k][bi + lw + 1])
              ? treeV[k][bi + lw]
              : treeV[k][bi + lw + 1];
          treeV[k + 1][(m >> 1) * ((lw + 1) >> 1) + (n >> 1)] =
              tm1 < tm2 ? tm1 : tm2;
        }
        // Now we may have quad with 1 column, 2 lines
        if (lw % 2 != 0) {
          n = ((lw >> 1) << 1);
          // Take minimum of 2 elements and put it in higher
          // level
          bi = m * lw + n;
          treeV[k + 1][(m >> 1) * ((lw + 1) >> 1) + (n >> 1)] =
              (treeV[k][bi] < treeV[k][bi + lw])
                  ? treeV[k][bi]
                  : treeV[k][bi + lw];
        }
      }
      // Now we may have quads with 1 line, 2 or 1 columns
      if (lh % 2 != 0) {
        m = ((lh >> 1) << 1);
        for (n = ((lw >> 1) << 1) - 2; n >= 0; n -= 2) {
          // All quads with 2 columns
          // Take minimum of 2 elements and put it in higher
          // level
          bi = m * lw + n;
          treeV[k + 1][(m >> 1) * ((lw + 1) >> 1) + (n >> 1)] =
              (treeV[k][bi] < treeV[k][bi + 1]) ? treeV[k][bi] : treeV[k][bi + 1];
        }
        // Now we may have quad with 1 column, 1 line
        if (lw % 2 != 0) {
          // Just copy the value
          n = ((lw >> 1) << 1);
          treeV[k + 1][(m >> 1) * ((lw + 1) >> 1) + (n >> 1)] =
              treeV[k][m * lw + n];
        }
      }
    }
  }

  /// Changes the value of a leaf in the tag tree. The new and old values of
  /// the element must be not smaller than the largest threshold which has
  /// yet been supplied to 'encode()'.
  ///
  /// [m] The vertical index of the element.
  ///
  /// [n] The horizontal index of the element.
  ///
  /// [v] The new value of the element.
  void setValue(int m, int n, int v) {
    int k, idx;
    // Check arguments
    if (lvls == 0 ||
        n < 0 ||
        n >= w ||
        v < treeS[lvls - 1][0] ||
        treeV[0][m * w + n] < treeS[lvls - 1][0]) {
      throw ArgumentError();
    }
    // Update the leaf value
    treeV[0][m * w + n] = v;
    // Update all parents
    for (k = 1; k < lvls; k++) {
      idx = (m >> k) * ((w + (1 << k) - 1) >> k) + (n >> k);
      if (v < treeV[k][idx]) {
        // We need to update minimum and continue checking
        // in higher levels
        treeV[k][idx] = v;
      } else {
        // We are done: v is equal or less to minimum
        // in this level, no other minimums to update.
        break;
      }
    }
  }

  /// Sets the values of the leafs to the new set of values and updates the
  /// tag tree accordingly. No leaf can change its value if either the new or
  /// old value is smaller than largest threshold which has yet been supplied
  /// to 'encode()'. However such a leaf can keep its old value (i.e. new and
  /// old value must be identical.
  ///
  /// This method is more efficient than the setValue() method if a large
  /// proportion of the leafs change their value. Note that for leafs which
  /// don't have their value defined yet the value should be
  /// Integer.MAX_VALUE (which is the default initialization value).
  ///
  /// [val] The new values for the leafs, in lexicographical order.
  void setValues(List<int> val) {
    int i, maxt;
    if (lvls == 0) {
      // Can't set values on empty tree
      throw ArgumentError();
    }
    // Check the values
    maxt = treeS[lvls - 1][0];
    for (i = w * h - 1; i >= 0; i--) {
      if ((treeV[0][i] < maxt || val[i] < maxt) && treeV[0][i] != val[i]) {
        throw ArgumentError();
      }
      // Update leaf value
      treeV[0][i] = val[i];
    }
    // Recalculate tree at other levels
    _recalcTreeV();
  }

  /// Encodes information for the specified element of the tree, given the
  /// threshold and sends it to the 'out' stream. The information that is
  /// coded is whether or not the value of the element is greater than or
  /// equal to the value of the threshold.
  ///
  /// [m] The vertical index of the element.
  ///
  /// [n] The horizontal index of the element.
  ///
  /// [t] The threshold to use for encoding. It must be non-negative.
  ///
  /// [out] The stream where to write the coded information.
  void encode(int m, int n, int t, BitOutputBuffer out) {
    int k, ts, idx, tmin;

    // Check arguments
    if (m >= h || n >= w || t < 0) {
      throw ArgumentError();
    }

    // Initialize
    k = lvls - 1;
    tmin = treeS[k][0];

    // Loop on levels
    while (true) {
      // Index of element in level 'k'
      idx = (m >> k) * ((w + (1 << k) - 1) >> k) + (n >> k);
      // Cache state
      ts = treeS[k][idx];
      if (ts < tmin) {
        ts = tmin;
      }
      while (t > ts) {
        if (treeV[k][idx] > ts) {
          out.writeBit(0); // Send '0' bit
        } else if (treeV[k][idx] == ts) {
          out.writeBit(1); // Send '1' bit
        } else {
          // we are done: set ts and get out of this while
          ts = t;
          break;
        }
        // Increment of treeS[k][idx]
        ts++;
      }
      // Update state
      treeS[k][idx] = ts;
      // Update tmin or terminate
      if (k > 0) {
        tmin = ts < treeV[k][idx] ? ts : treeV[k][idx];
        k--;
      } else {
        // Terminate
        return;
      }
    }
  }

  /// Saves the current values and state of the tree. Calling restore()
  /// restores the tag tree the saved state.
  void save() {
    int k;

    if (treeVbak == null) {
      // Nothing saved yet
      // Allocate saved arrays
      // treeV and treeS have the same dimensions
      treeVbak = List.generate(lvls, (_) => []);
      treeSbak = List.generate(lvls, (_) => []);
      for (k = lvls - 1; k >= 0; k--) {
        treeVbak![k] = List.filled(treeV[k].length, 0);
        treeSbak![k] = List.filled(treeV[k].length, 0);
      }
    }

    // Copy the arrays
    for (k = treeV.length - 1; k >= 0; k--) {
      List.copyRange(treeVbak![k], 0, treeV[k]);
      List.copyRange(treeSbak![k], 0, treeS[k]);
    }

    // Set saved state
    saved = true;
  }

  /// Restores the saved values and state of the tree. An
  /// IllegalArgumentException is thrown if the tree values and state have
  /// not been saved yet.
  void restore() {
    int k;

    if (!saved) {
      // Nothing saved yet
      throw ArgumentError();
    }

    // Copy the arrays
    for (k = lvls - 1; k >= 0; k--) {
      List.copyRange(treeV[k], 0, treeVbak![k]);
      List.copyRange(treeS[k], 0, treeSbak![k]);
    }
  }

  /// Resets the tree values and state. All the values are set to
  /// Integer.MAX_VALUE and the states to 0.
  void reset([List<int>? val]) {
    int k;
    if (val == null) {
      // Set all values to Integer.MAX_VALUE
      // and states to 0
      for (k = lvls - 1; k >= 0; k--) {
        ArrayUtil.intArraySet(treeV[k], 2147483647);
        ArrayUtil.intArraySet(treeS[k], 0);
      }
    } else {
      // Set values for leaf level
      for (k = w * h - 1; k >= 0; k--) {
        treeV[0][k] = val[k];
      }
      // Calculate values at other levels
      _recalcTreeV();
      // Set all states to 0
      for (k = lvls - 1; k >= 0; k--) {
        ArrayUtil.intArraySet(treeS[k], 0);
      }
    }
    // Invalidate saved tree
    saved = false;
  }
}

