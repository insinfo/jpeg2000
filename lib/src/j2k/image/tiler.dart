import '../NoNextElementException.dart';
import 'BlkImgDataSrc.dart';
import 'Coord.dart';
import 'DataBlk.dart';
import 'ImgDataAdapter.dart';

/// This class places an image in the canvas coordinate system, tiles it, if so
/// specified, and performs the coordinate conversions transparently. The
/// source must be a 'BlkImgDataSrc' which is not tiled and has a the image
/// origin at the canvas origin (i.e. it is not "canvased"), or an exception is
/// thrown by the constructor. A tiled and "canvased" output is given through
/// the 'BlkImgDataSrc' interface. See the 'ImgData' interface for a
/// description of the canvas and tiling.
///
/// All tiles produced are rectangular, non-overlapping and their union
/// covers all the image. However, the tiling may not be uniform, depending on
/// the nominal tile size, tiling origin, component subsampling and other
/// factors. Therefore it might not be assumed that all tiles are of the same
/// width and height.
///
/// The nominal dimension of the tiles is the maximal one, in the reference
/// grid. All the components of the image have the same number of tiles.
class Tiler extends ImgDataAdapter implements BlkImgDataSrc {
  /// The source of image data
  late final BlkImgDataSrc src;

  /// Horizontal coordinate of the upper left hand reference grid point.
  final int x0siz;

  /// Vertical coordinate of the upper left hand reference grid point.
  final int y0siz;

  /// The horizontal coordinate of the tiling origin in the canvas system,
  /// on the reference grid.
  int xt0siz;

  /// The vertical coordinate of the tiling origin in the canvas system, on
  /// the reference grid.
  int yt0siz;

  /// The nominal width of the tiles, on the reference grid. If 0 then there
  /// is no tiling in that direction.
  int xtsiz;

  /// The nominal height of the tiles, on the reference grid. If 0 then
  /// there is no tiling in that direction.
  int ytsiz;

  /// The number of tiles in the horizontal direction.
  late final int ntX;

  /// The number of tiles in the vertical direction.
  late final int ntY;

  /// The component width in the current active tile, for each component
  List<int>? compW;

  /// The component height in the current active tile, for each component
  List<int>? compH;

  /// The horizontal coordinates of the upper-left corner of the components
  /// in the current tile
  List<int>? tcx0;

  /// The vertical coordinates of the upper-left corner of the components in
  /// the current tile.
  List<int>? tcy0;

  /// The horizontal index of the current tile
  int tx = 0;

  /// The vertical index of the current tile
  int ty = 0;

  /// The width of the current tile, on the reference grid.
  int tileW = 0;

  /// The height of the current tile, on the reference grid.
  int tileH = 0;

  /// Constructs a new tiler with the specified 'BlkImgDataSrc' source,
  /// image origin, tiling origin and nominal tile size.
  ///
  /// @param src The 'BlkImgDataSrc' source from where to get the image
  /// data. It must not be tiled and the image origin must be at '(0,0)' on
  /// its canvas.
  ///
  /// @param ax The horizontal coordinate of the image origin in the canvas
  /// system, on the reference grid (i.e. the image's top-left corner in the
  /// reference grid).
  ///
  /// @param ay The vertical coordinate of the image origin in the canvas
  /// system, on the reference grid (i.e. the image's top-left corner in the
  /// reference grid).
  ///
  /// @param px The horizontal tiling origin, in the canvas system, on the
  /// reference grid. It must satisfy 'px<=ax'.
  ///
  /// @param py The vertical tiling origin, in the canvas system, on the
  /// reference grid. It must satisfy 'py<=ay'.
  ///
  /// @param nw The nominal tile width, on the reference grid. If 0 then
  /// there is no tiling in that direction.
  ///
  /// @param nh The nominal tile height, on the reference grid. If 0 then
  /// there is no tiling in that direction.
  ///
  /// @exception IllegalArgumentException If src is tiled or "canvased", or
  /// if the arguments do not satisfy the specified constraints.
  Tiler(BlkImgDataSrc src, int ax, int ay, int px, int py, int nw, int nh)
      : x0siz = ax,
        y0siz = ay,
        xt0siz = px,
        yt0siz = py,
        xtsiz = nw,
        ytsiz = nh,
        super(src) {
    this.src = src;

    // Verify that input is not tiled
    if (src.getNumTiles() != 1) {
      throw ArgumentError("Source is tiled");
    }
    // Verify that source is not "canvased"
    if (src.getImgULX() != 0 || src.getImgULY() != 0) {
      throw ArgumentError("Source is \"canvased\"");
    }
    // Verify that arguments satisfy trivial requirements
    if (x0siz < 0 ||
        y0siz < 0 ||
        xt0siz < 0 ||
        yt0siz < 0 ||
        xtsiz < 0 ||
        ytsiz < 0 ||
        xt0siz > x0siz ||
        yt0siz > y0siz) {
      throw ArgumentError(
          "Invalid image origin, tiling origin or nominal tile size");
    }

    // If no tiling has been specified, creates a unique tile with maximum
    // dimension.
    if (xtsiz == 0) xtsiz = x0siz + src.getImgWidth() - xt0siz;
    if (ytsiz == 0) ytsiz = y0siz + src.getImgHeight() - yt0siz;

    // Automatically adjusts xt0siz,yt0siz so that tile (0,0) always
    // overlaps with the image.
    if (x0siz - xt0siz >= xtsiz) {
      xt0siz += ((x0siz - xt0siz) ~/ xtsiz) * xtsiz;
    }
    if (y0siz - yt0siz >= ytsiz) {
      yt0siz += ((y0siz - yt0siz) ~/ ytsiz) * ytsiz;
    }
    if (x0siz - xt0siz >= xtsiz || y0siz - yt0siz >= ytsiz) {
      // FacilityManager.getMsgLogger().printmsg(MsgLogger.INFO, ...);
      // print("Automatically adjusted tiling origin...");
    }

    // Calculate the number of tiles
    ntX = ((x0siz + src.getImgWidth()) / xtsiz).ceil();
    ntY = ((y0siz + src.getImgHeight()) / ytsiz).ceil();
  }

  /// Returns the overall width of the current tile in pixels. This is the
  /// tile's width without accounting for any component subsampling.
  ///
  /// @return The total current tile width in pixels.
  @override
  int getTileWidth() {
    return tileW;
  }

  /// Returns the overall height of the current tile in pixels. This is the
  /// tile's width without accounting for any component subsampling.
  ///
  /// @return The total current tile height in pixels.
  @override
  int getTileHeight() {
    return tileH;
  }

  /// Returns the width in pixels of the specified tile-component.
  ///
  /// @param t Tile index
  ///
  /// @param c The index of the component, from 0 to N-1.
  ///
  /// @return The width of specified tile-component.
  @override
  int getTileCompWidth(int t, int c) {
    if (t != getTileIdx()) {
      throw Error(); // "Asking the width of a tile-component which is not in the current tile..."
    }
    return compW![c];
  }

  /// Returns the height in pixels of the specified tile-component.
  ///
  /// @param t The tile index.
  ///
  /// @param c The index of the component, from 0 to N-1.
  ///
  /// @return The height of specified tile-component.
  @override
  int getTileCompHeight(int t, int c) {
    if (t != getTileIdx()) {
      throw Error(); // "Asking the width of a tile-component which is not in the current tile..."
    }
    return compH![c];
  }

  /// Returns the position of the fixed point in the specified
  /// component. This is the position of the least significant integral
  /// (i.e. non-fractional) bit, which is equivalent to the number of
  /// fractional bits. For instance, for fixed-point values with 2 fractional
  /// bits, 2 is returned. For floating-point data this value does not apply
  /// and 0 should be returned. Position 0 is the position of the least
  /// significant bit in the data.
  ///
  /// @param c The index of the component.
  ///
  /// @return The position of the fixed-point, which is the same as the
  /// number of fractional bits. For floating-point data 0 is returned.
  @override
  int getFixedPoint(int c) {
    return src.getFixedPoint(c);
  }

  /// Returns, in the blk argument, a block of image data containing the
  /// specifed rectangular area, in the specified component. The data is
  /// returned, as a reference to the internal data, if any, instead of as a
  /// copy, therefore the returned data should not be modified.
  ///
  /// @param blk Its coordinates and dimensions specify the area to return,
  /// relative to the current tile. Some fields in this object are modified
  /// to return the data.
  ///
  /// @param c The index of the component from which to get the data.
  ///
  /// @return The requested DataBlk
  @override
  DataBlk getInternCompData(DataBlk blk, int c) {
    // Check that block is inside tile
    if (blk.ulx < 0 ||
        blk.uly < 0 ||
        blk.w > compW![c] ||
        blk.h > compH![c]) {
      throw ArgumentError("Block is outside the tile");
    }
    // Translate to the sources coordinates
    int incx = (x0siz / src.getCompSubsX(c)).ceil();
    int incy = (y0siz / src.getCompSubsY(c)).ceil();
    blk.ulx -= incx;
    blk.uly -= incy;
    blk = src.getInternCompData(blk, c);
    // Translate back to the tiled coordinates
    blk.ulx += incx;
    blk.uly += incy;
    return blk;
  }

  /// Returns, in the blk argument, a block of image data containing the
  /// specifed rectangular area, in the specified component. The data is
  /// returned, as a copy of the internal data, therefore the returned data
  /// can be modified "in place".
  ///
  /// @param blk Its coordinates and dimensions specify the area to return,
  /// relative to the current tile. If it contains a non-null data array,
  /// then it must be large enough. If it contains a null data array a new
  /// one is created. Some fields in this object are modified to return the
  /// data.
  ///
  /// @param c The index of the component from which to get the data.
  ///
  /// @return The requested DataBlk
  @override
  DataBlk getCompData(DataBlk blk, int c) {
    // Check that block is inside tile
    if (blk.ulx < 0 ||
        blk.uly < 0 ||
        blk.w > compW![c] ||
        blk.h > compH![c]) {
      throw ArgumentError("Block is outside the tile");
    }
    // Translate to the source's coordinates
    int incx = (x0siz / src.getCompSubsX(c)).ceil();
    int incy = (y0siz / src.getCompSubsY(c)).ceil();
    blk.ulx -= incx;
    blk.uly -= incy;
    blk = src.getCompData(blk, c);
    // Translate back to the tiled coordinates
    blk.ulx += incx;
    blk.uly += incy;
    return blk;
  }

  /// Changes the current tile, given the new tile indexes. An
  /// IllegalArgumentException is thrown if the coordinates do not correspond
  /// to a valid tile.
  ///
  /// @param x The horizontal index of the tile.
  ///
  /// @param y The vertical index of the new tile.
  @override
  void setTile(int x, int y) {
    // Check tile indexes
    if (x < 0 || y < 0 || x >= ntX || y >= ntY) {
      throw ArgumentError("Tile's indexes out of bounds");
    }

    // Set new current tile
    tx = x;
    ty = y;
    // Calculate tile origins
    int tx0 = (x != 0) ? xt0siz + x * xtsiz : x0siz;
    int ty0 = (y != 0) ? yt0siz + y * ytsiz : y0siz;
    int tx1 = (x != ntX - 1)
        ? (xt0siz + (x + 1) * xtsiz)
        : (x0siz + src.getImgWidth());
    int ty1 = (y != ntY - 1)
        ? (yt0siz + (y + 1) * ytsiz)
        : (y0siz + src.getImgHeight());
    // Set general variables
    tileW = tx1 - tx0;
    tileH = ty1 - ty0;
    // Set component specific variables
    int nc = src.getNumComps();
    if (compW == null) compW = List.filled(nc, 0);
    if (compH == null) compH = List.filled(nc, 0);
    if (tcx0 == null) tcx0 = List.filled(nc, 0);
    if (tcy0 == null) tcy0 = List.filled(nc, 0);
    for (int i = 0; i < nc; i++) {
      tcx0![i] = (tx0 / src.getCompSubsX(i)).ceil();
      tcy0![i] = (ty0 / src.getCompSubsY(i)).ceil();
      compW![i] = (tx1 / src.getCompSubsX(i)).ceil() - tcx0![i];
      compH![i] = (ty1 / src.getCompSubsY(i)).ceil() - tcy0![i];
    }
  }

  /// Advances to the next tile, in standard scan-line order (by rows then
  /// columns). An NoNextElementException is thrown if the current tile is
  /// the last one (i.e. there is no next tile).
  @override
  void nextTile() {
    if (tx == ntX - 1 && ty == ntY - 1) {
      // Already at last tile
      throw NoNextElementException();
    } else if (tx < ntX - 1) {
      // If not at end of current tile line
      setTile(tx + 1, ty);
    } else {
      // First tile at next line
      setTile(0, ty + 1);
    }
  }

  /// Returns the horizontal and vertical indexes of the current tile.
  ///
  /// @param co If not null this object is used to return the
  /// information. If null a new one is created and returned.
  ///
  /// @return The current tile's horizontal and vertical indexes..
  @override
  Coord getTile(Coord? co) {
    if (co != null) {
      co.x = tx;
      co.y = ty;
      return co;
    } else {
      return Coord(tx, ty);
    }
  }

  /// Returns the index of the current tile, relative to a standard scan-line
  /// order.
  ///
  /// @return The current tile's index (starts at 0).
  @override
  int getTileIdx() {
    return ty * ntX + tx;
  }

  /// Returns the horizontal coordinate of the upper-left corner of the
  /// specified component in the current tile.
  ///
  /// @param c The component index.
  @override
  int getCompULX(int c) {
    return tcx0![c];
  }

  /// Returns the vertical coordinate of the upper-left corner of the
  /// specified component in the current tile.
  ///
  /// @param c The component index.
  @override
  int getCompULY(int c) {
    return tcy0![c];
  }

  /// Returns the horizontal tile partition offset in the reference grid
  @override
  int getTilePartULX() {
    return xt0siz;
  }

  /// Returns the vertical tile partition offset in the reference grid
  @override
  int getTilePartULY() {
    return yt0siz;
  }

  /// Returns the horizontal coordinate of the image origin, the top-left
  /// corner, in the canvas system, on the reference grid.
  ///
  /// @return The horizontal coordinate of the image origin in the canvas
  /// system, on the reference grid.
  @override
  int getImgULX() {
    return x0siz;
  }

  /// Returns the vertical coordinate of the image origin, the top-left
  /// corner, in the canvas system, on the reference grid.
  ///
  /// @return The vertical coordinate of the image origin in the canvas
  /// system, on the reference grid.
  @override
  int getImgULY() {
    return y0siz;
  }

  /// Returns the number of tiles in the horizontal and vertical directions.
  ///
  /// @param co If not null this object is used to return the information. If
  /// null a new one is created and returned.
  ///
  /// @return The number of tiles in the horizontal (Coord.x) and vertical
  /// (Coord.y) directions.
  @override
  Coord getNumTilesCoord(Coord? co) {
    if (co != null) {
      co.x = ntX;
      co.y = ntY;
      return co;
    } else {
      return Coord(ntX, ntY);
    }
  }

  /// Returns the total number of tiles in the image.
  ///
  /// @return The total number of tiles in the image.
  @override
  int getNumTiles() {
    return ntX * ntY;
  }

  /// Returns the nominal width of the tiles in the reference grid.
  ///
  /// @return The nominal tile width, in the reference grid.
  @override
  int getNomTileWidth() {
    return xtsiz;
  }

  /// Returns the nominal width of the tiles in the reference grid.
  ///
  /// @return The nominal tile width, in the reference grid.
  @override
  int getNomTileHeight() {
    return ytsiz;
  }

  /// Returns the tiling origin, referred to as '(xt0siz,yt0siz)' in the
  /// codestream header (SIZ marker segment).
  ///
  /// @param co If not null this object is used to return the information. If
  /// null a new one is created and returned.
  ///
  /// @return The coordinate of the tiling origin, in the canvas system, on
  /// the reference grid.
  ///
  /// @see ImgData
  Coord getTilingOrigin(Coord? co) {
    if (co != null) {
      co.x = xt0siz;
      co.y = yt0siz;
      return co;
    } else {
      return Coord(xt0siz, yt0siz);
    }
  }

  /// Returns a String object representing Tiler's informations
  ///
  /// @return Tiler's infos in a string
  @override
  String toString() {
    return "Tiler: source= $src\n${getNumTiles()} tile(s), nominal width=$xtsiz, nominal height=$ytsiz";
  }
}

