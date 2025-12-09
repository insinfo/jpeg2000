import '../../util/ArrayUtil.dart';
import '../StdEntropyCoderOptions.dart';
import 'ByteOutputBuffer.dart';

/// This class implements the MQ arithmetic coder. When initialized a specific
/// state can be specified for each context, which may be adapted to the
/// probability distribution that is expected for that context.
///
/// The type of length calculation and termination can be chosen at
/// construction time.
class MQCoder {
  /// Identifier for the lazy length calculation. The lazy length
  /// calculation is not optimal but is extremely simple.
  static const int LENGTH_LAZY = 0;

  /// Identifier for a very simple length calculation. This provides better
  /// results than the 'LENGTH_LAZY' computation. This is the old length
  /// calculation that was implemented in this class.
  static const int LENGTH_LAZY_GOOD = 1;

  /// Identifier for the near optimal length calculation. This calculation
  /// is more complex than the lazy one but provides an almost optimal length
  /// calculation.
  static const int LENGTH_NEAR_OPT = 2;

  /// The identifier fort the termination that uses a full flush. This is
  /// the less efficient termination.
  static const int TERM_FULL = 0;

  /// The identifier for the termination that uses the near optimal length
  /// calculation to terminate the arithmetic codewrod
  static const int TERM_NEAR_OPT = 1;

  /// The identifier for the easy termination that is simpler than the
  /// 'TERM_NEAR_OPT' one but slightly less efficient.
  static const int TERM_EASY = 2;

  /// The identifier for the predictable termination policy for error
  /// resilience. This is the same as the 'TERM_EASY' one but an special
  /// sequence of bits is embodied in the spare bits for error resilience
  /// purposes.
  static const int TERM_PRED_ER = 3;

  /// The data structures containing the probabilities for the LPS
  static const List<int> qe = [
    0x5601, 0x3401, 0x1801, 0x0ac1, 0x0521, 0x0221, 0x5601,
    0x5401, 0x4801, 0x3801, 0x3001, 0x2401, 0x1c01, 0x1601,
    0x5601, 0x5401, 0x5101, 0x4801, 0x3801, 0x3401, 0x3001,
    0x2801, 0x2401, 0x2201, 0x1c01, 0x1801, 0x1601, 0x1401,
    0x1201, 0x1101, 0x0ac1, 0x09c1, 0x08a1, 0x0521, 0x0441,
    0x02a1, 0x0221, 0x0141, 0x0111, 0x0085, 0x0049, 0x0025,
    0x0015, 0x0009, 0x0005, 0x0001, 0x5601
  ];

  /// The indexes of the next MPS
  static const List<int> nMPS = [
    1, 2, 3, 4, 5, 38, 7, 8, 9, 10, 11, 12, 13, 29, 15, 16, 17,
    18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
    35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 45, 46
  ];

  /// The indexes of the next LPS
  static const List<int> nLPS = [
    1, 6, 9, 12, 29, 33, 6, 14, 14, 14, 17, 18, 20, 21, 14, 14, 15,
    16, 17, 18, 19, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
    32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 46
  ];

  /// Whether LPS and MPS should be switched
  static const List<int> switchLM = [
    1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  ];

  /// The ByteOutputBuffer used to write the compressed bit stream.
  ByteOutputBuffer out;

  /// The current most probable signal for each context
  late List<int> mPS;

  /// The current index of each context
  late List<int> I;

  /// The current bit code
  int c = 0;

  /// The bit code counter
  int cT = 0;

  /// The current interval
  int a = 0;

  /// The last encoded byte of data
  int b = 0;

  /// If a 0xFF byte has been delayed and not yet been written to the output
  /// (in the MQ we can never have more than 1 0xFF byte in a row).
  bool delFF = false;

  /// The number of written bytes so far, excluding any delayed 0xFF
  /// bytes. Upon initialization it is -1 to indicated that the byte buffer
  /// 'b' is empty as well.
  int nrOfWrittenBytes = -1;

  /// The initial state of each context
  List<int> initStates;

  /// The termination type to use. One of 'TERM_FULL', 'TERM_NEAR_OPT',
  /// 'TERM_EASY' or 'TERM_PRED_ER'.
  int ttype = 0;

  /// The length calculation type to use. One of 'LENGTH_LAZY',
  /// 'LENGTH_LAZY_GOOD', 'LENGTH_NEAR_OPT'.
  int ltype = 0;

  /// Saved values of the C register. Used for the LENGTH_NEAR_OPT length
  /// calculation.
  List<int>? savedC;

  /// Saved values of CT counter. Used for the LENGTH_NEAR_OPT length
  /// calculation.
  List<int>? savedCT;

  /// Saved values of the A register. Used for the LENGTH_NEAR_OPT length
  /// calculation.
  List<int>? savedA;

  /// Saved values of the B byte buffer. Used for the LENGTH_NEAR_OPT length
  /// calculation.
  List<int>? savedB;

  /// Saved values of the delFF (i.e. delayed 0xFF) state. Used for the
  /// LENGTH_NEAR_OPT length calculation.
  List<bool>? savedDelFF;

  /// Number of saved states. Used for the LENGTH_NEAR_OPT length
  /// calculation.
  int nSaved = 0;

  /// The initial length of the arrays to save sates
  static const int SAVED_LEN = 32 * StdEntropyCoderOptions.NUM_PASSES;

  /// The increase in length for the arrays to save states
  static const int SAVED_INC = 4 * StdEntropyCoderOptions.NUM_PASSES;

  /// Instantiates a new MQ-coder, with the specified number of contexts and
  /// initial states. The compressed bytestream is written to the 'oStream'
  /// object.
  ///
  /// [oStream] where to output the compressed data.
  ///
  /// [nrOfContexts] The number of contexts used by the MQ coder.
  ///
  /// [init] The initial state for each context. A reference is kept to
  /// this array to reinitialize the contexts whenever 'reset()' or
  /// 'resetCtxts()' is called.
  MQCoder(this.out, int nrOfContexts, this.initStates) {
    // --- INITENC

    // Default initialization of the statistics bins is MPS=0 and
    // I=0
    I = List<int>.filled(nrOfContexts, 0);
    mPS = List<int>.filled(nrOfContexts, 0);

    a = 0x8000;
    c = 0;
    if (b == 0xFF) {
      cT = 13;
    } else {
      cT = 12;
    }

    resetCtxts();

    // End of INITENC ---
    b = 0;
  }

  /// Set the length calculation type to the specified type.
  ///
  /// [ltype] The type of length calculation to use. One of
  /// 'LENGTH_LAZY', 'LENGTH_LAZY_GOOD' or 'LENGTH_NEAR_OPT'.
  void setLenCalcType(int ltype) {
    // Verify the ttype and ltype
    if (ltype != LENGTH_LAZY &&
        ltype != LENGTH_LAZY_GOOD &&
        ltype != LENGTH_NEAR_OPT) {
      throw ArgumentError("Unrecognized length calculation type code: $ltype");
    }

    if (ltype == LENGTH_NEAR_OPT) {
      if (savedC == null) savedC = List<int>.filled(SAVED_LEN, 0);
      if (savedCT == null) savedCT = List<int>.filled(SAVED_LEN, 0);
      if (savedA == null) savedA = List<int>.filled(SAVED_LEN, 0);
      if (savedB == null) savedB = List<int>.filled(SAVED_LEN, 0);
      if (savedDelFF == null) savedDelFF = List<bool>.filled(SAVED_LEN, false);
    }
    this.ltype = ltype;
  }

  /// Set termination type to the specified type.
  ///
  /// [ttype] The type of termination to use. One of 'TERM_FULL',
  /// 'TERM_NEAR_OPT', 'TERM_EASY' or 'TERM_PRED_ER'.
  void setTermType(int ttype) {
    if (ttype != TERM_FULL &&
        ttype != TERM_NEAR_OPT &&
        ttype != TERM_EASY &&
        ttype != TERM_PRED_ER) {
      throw ArgumentError("Unrecognized termination type code: $ttype");
    }
    this.ttype = ttype;
  }

  /// This method performs the coding of the symbol 'bit', using context
  /// 'ctxt', 'n' times, using the MQ-coder speedup mode if possible.
  ///
  /// If the symbol 'bit' is the current more probable symbol (MPS) and
  /// qe[ctxt]<=0x4000, and (A-0x8000)>=qe[ctxt], speedup mode will be
  /// used. Otherwise the normal mode will be used. The speedup mode can
  /// significantly improve the speed of arithmetic coding when several MPS
  /// symbols, with a high probability distribution, must be coded with the
  /// same context. The generated bit stream is the same as if the normal mode
  /// was used.
  ///
  /// This method is also faster than the 'codeSymbols()' and
  /// 'codeSymbol()' ones, for coding the same symbols with the same context
  /// several times, when speedup mode can not be used, although not
  /// significantly.
  ///
  /// [bit] The symbol do code, 0 or 1.
  ///
  /// [ctxt] The context to us in coding the symbol.
  ///
  /// [n] The number of times that the symbol must be coded.
  void fastCodeSymbols(int bit, int ctxt, int n) {
    int q; // cache for context's Qe
    int la; // cache for A register
    int nc; // counter for renormalization shifts
    int ns; // the maximum length of a speedup mode run
    int li; // cache for I[ctxt]

    li = I[ctxt]; // cache current index
    q = qe[li]; // retrieve current LPS prob.

    if ((q <= 0x4000) &&
        (bit == mPS[ctxt]) &&
        ((ns = (a - 0x8000) ~/ q + 1) > 1)) {
      // Do speed up mode
      // coding MPS, no conditional exchange can occur and
      // speedup mode is possible for more than 1 symbol
      do {
        // do as many speedup runs as necessary
        if (n <= ns) {
          // All symbols in this run
          // code 'n' symbols
          la = n * q; // accumulated Q
          a -= la;
          c += la;
          if (a >= 0x8000) {
            // no renormalization
            I[ctxt] = li; // save the current state
            return; // done
          }
          I[ctxt] = nMPS[li]; // goto next state and save it
          // -- Renormalization (MPS: no need for while loop)
          a <<= 1; // a is doubled
          c <<= 1; // c is doubled
          cT--;
          if (cT == 0) {
            byteOut();
          }
          // -- End of renormalization
          return; // done
        } else {
          // Not all symbols in this run
          // code 'ns' symbols
          la = ns * q; // accumulated Q
          c += la;
          a -= la;
          // cache li and q for next iteration
          li = nMPS[li];
          q = qe[li]; // New q is always less than current one
          // new I[ctxt] is stored in last run
          // Renormalization always occurs since we exceed 'ns'
          // -- Renormalization (MPS: no need for while loop)
          a <<= 1; // a is doubled
          c <<= 1; // c is doubled
          cT--;
          if (cT == 0) {
            byteOut();
          }
          // -- End of renormalization
          n -= ns; // symbols left to code
          ns = (a - 0x8000) ~/ q + 1; // max length of next speedup run
          continue; // goto next iteration
        }
      } while (n > 0);
    } // end speed up mode
    else {
      // No speedup mode
      // Either speedup mode is not possible or not worth doing it
      // because of probable conditional exchange
      // Code everything as in normal mode
      la = a; // cache A register in local variable
      do {
        if (bit == mPS[ctxt]) {
          // -- code MPS
          la -= q; // Interval division associated with MPS coding
          if (la >= 0x8000) {
            // Interval big enough
            c += q;
          } else {
            // Interval too short
            if (la < q) {
              // Probabilities are inverted
              la = q;
            } else {
              c += q;
            }
            // cache new li and q for next iteration
            li = nMPS[li];
            q = qe[li];
            // new I[ctxt] is stored after end of loop
            // -- Renormalization (MPS: no need for while loop)
            la <<= 1; // a is doubled
            c <<= 1; // c is doubled
            cT--;
            if (cT == 0) {
              byteOut();
            }
            // -- End of renormalization
          }
        } else {
          // -- code LPS
          la -= q; // Interval division according to LPS coding
          if (la < q) {
            c += q;
          } else {
            la = q;
          }
          if (switchLM[li] != 0) {
            mPS[ctxt] = 1 - mPS[ctxt];
          }
          // cache new li and q for next iteration
          li = nLPS[li];
          q = qe[li];
          // new I[ctxt] is stored after end of loop
          // -- Renormalization
          // sligthly better than normal loop
          nc = 0;
          do {
            la <<= 1;
            nc++; // count number of necessary shifts
          } while (la < 0x8000);
          if (cT > nc) {
            c <<= nc;
            cT -= nc;
          } else {
            do {
              c <<= cT;
              nc -= cT;
              // cT = 0; // not necessary
              byteOut();
            } while (cT <= nc);
            c <<= nc;
            cT -= nc;
          }
          // -- End of renormalization
        }
        n--;
      } while (n > 0);
      I[ctxt] = li; // store new I[ctxt]
      a = la; // save cached A register
    }
  }

  /// This function performs the arithmetic encoding of several symbols
  /// together. The function receives an array of symbols that are to be
  /// encoded and an array containing the contexts with which to encode them.
  ///
  /// The advantage of using this function is that the cost of the method
  /// call is amortized by the number of coded symbols per method call.
  ///
  /// Each context has a current MPS and an index describing what the
  /// current probability is for the LPS. Each bit is encoded and if the
  /// probability of the LPS exceeds .5, the MPS and LPS are switched.
  ///
  /// [bits] An array containing the symbols to be encoded. Valid
  /// symbols are 0 and 1.
  ///
  /// [cX] The context for each of the symbols to be encoded.
  ///
  /// [n] The number of symbols to encode.
  void codeSymbols(List<int> bits, List<int> cX, int n) {
    int q;
    int li; // local cache of I[context]
    int la;
    int nc;
    int ctxt; // context of current symbol
    int i; // counter

    // NOTE: here we could use symbol aggregation to speed things up.
    // It remains to be studied.

    la = a; // cache A register in local variable
    for (i = 0; i < n; i++) {
      // NOTE: (a<0x8000) is equivalent to ((a&0x8000)==0)
      // since 'a' is always less than or equal to 0xFFFF

      // NOTE: conditional exchange guarantees that A for MPS is
      // always greater than 0x4000 (i.e. 0.375)
      // => one renormalization shift is enough for MPS
      // => no need to do a renormalization while loop for MPS

      ctxt = cX[i];
      li = I[ctxt];
      q = qe[li]; // Retrieve current LPS prob.

      if (bits[i] == mPS[ctxt]) {
        // -- Code MPS

        la -= q; // Interval division associated with MPS coding

        if (la >= 0x8000) {
          // Interval big enough
          c += q;
        } else {
          // Interval too short
          if (la < q) {
            // Probabilities are inverted
            la = q;
          } else {
            c += q;
          }

          I[ctxt] = nMPS[li];

          // -- Renormalization (MPS: no need for while loop)
          la <<= 1; // a is doubled
          c <<= 1; // c is doubled
          cT--;
          if (cT == 0) {
            byteOut();
          }
          // -- End of renormalization
        }
      } else {
        // -- Code LPS
        la -= q; // Interval division according to LPS coding

        if (la < q) {
          c += q;
        } else {
          la = q;
        }
        if (switchLM[li] != 0) {
          mPS[ctxt] = 1 - mPS[ctxt];
        }
        I[ctxt] = nLPS[li];

        // -- Renormalization

        // sligthly better than normal loop
        nc = 0;
        do {
          la <<= 1;
          nc++; // count number of necessary shifts
        } while (la < 0x8000);
        if (cT > nc) {
          c <<= nc;
          cT -= nc;
        } else {
          do {
            c <<= cT;
            nc -= cT;
            // cT = 0; // not necessary
            byteOut();
          } while (cT <= nc);
          c <<= nc;
          cT -= nc;
        }

        // -- End of renormalization
      }
    }
    a = la; // save cached A register
  }

  /// This function performs the arithmetic encoding of one symbol. The
  /// function receives a bit that is to be encoded and a context with which
  /// to encode it.
  ///
  /// Each context has a current MPS and an index describing what the
  /// current probability is for the LPS. Each bit is encoded and if the
  /// probability of the LPS exceeds .5, the MPS and LPS are switched.
  ///
  /// [bit] The symbol to be encoded, must be 0 or 1.
  ///
  /// [context] the context with which to encode the symbol.
  void codeSymbol(int bit, int context) {
    int q;
    int li; // local cache of I[context]
    int la;
    int n;

    // NOTE: (a < 0x8000) is equivalent to ((a & 0x8000)==0)
    // since 'a' is always less than or equal to 0xFFFF

    // NOTE: conditional exchange guarantees that A for MPS is
    // always greater than 0x4000 (i.e. 0.375)
    // => one renormalization shift is enough for MPS
    // => no need to do a renormalization while loop for MPS

    li = I[context];
    q = qe[li]; // Retrieve current LPS prob.

    if (bit == mPS[context]) {
      // -- Code MPS

      a -= q; // Interval division associated with MPS coding

      if (a >= 0x8000) {
        // Interval big enough
        c += q;
      } else {
        // Interval too short
        if (a < q) {
          // Probabilities are inverted
          a = q;
        } else {
          c += q;
        }

        I[context] = nMPS[li];

        // -- Renormalization (MPS: no need for while loop)
        a <<= 1; // a is doubled
        c <<= 1; // c is doubled
        cT--;
        if (cT == 0) {
          byteOut();
        }
        // -- End of renormalization
      }
    } else {
      // -- Code LPS

      la = a; // cache A register in local variable
      la -= q; // Interval division according to LPS coding

      if (la < q) {
        c += q;
      } else {
        la = q;
      }
      if (switchLM[li] != 0) {
        mPS[context] = 1 - mPS[context];
      }
      I[context] = nLPS[li];

      // -- Renormalization

      // sligthly better than normal loop
      n = 0;
      do {
        la <<= 1;
        n++; // count number of necessary shifts
      } while (la < 0x8000);
      if (cT > n) {
        c <<= n;
        cT -= n;
      } else {
        do {
          c <<= cT;
          n -= cT;
          // cT = 0; // not necessary
          byteOut();
        } while (cT <= n);
        c <<= n;
        cT -= n;
      }

      // -- End of renormalization
      a = la; // save cached A register
    }
  }

  /// This function puts one byte of compressed bits in the output stream.
  /// The highest 8 bits of c are then put in b to be the next byte to
  /// write. This method delays the output of any 0xFF bytes until a non 0xFF
  /// byte has to be written to the output bit stream (the 'delFF' variable
  /// signals if there is a delayed 0xff byte).
  void byteOut() {
    if (nrOfWrittenBytes >= 0) {
      if (b == 0xFF) {
        // Delay 0xFF byte
        delFF = true;
        b = c >>> 20;
        c &= 0xFFFFF;
        cT = 7;
      } else if (c < 0x8000000) {
        // Write delayed 0xFF bytes
        if (delFF) {
          out.write(0xFF);
          delFF = false;
          nrOfWrittenBytes++;
        }
        out.write(b);
        nrOfWrittenBytes++;
        b = c >>> 19;
        c &= 0x7FFFF;
        cT = 8;
      } else {
        b++;
        if (b == 0xFF) {
          // Delay 0xFF byte
          delFF = true;
          c &= 0x7FFFFFF;
          b = c >>> 20;
          c &= 0xFFFFF;
          cT = 7;
        } else {
          // Write delayed 0xFF bytes
          if (delFF) {
            out.write(0xFF);
            delFF = false;
            nrOfWrittenBytes++;
          }
          out.write(b);
          nrOfWrittenBytes++;
          b = ((c >>> 19) & 0xFF);
          c &= 0x7FFFF;
          cT = 8;
        }
      }
    } else {
      // NOTE: carry bit can never be set if the byte buffer was empty
      b = (c >>> 19);
      c &= 0x7FFFF;
      cT = 8;
      nrOfWrittenBytes++;
    }
  }

  /// This function flushes the remaining encoded bits and makes sure that
  /// enough information is written to the bit stream to be able to finish
  /// decoding, and then it reinitializes the internal state of the MQ coder
  /// but without modifying the context states.
  ///
  /// After calling this method the 'finishLengthCalculation()' method
  /// should be called, after compensating the returned length for the length
  /// of previous coded segments, so that the length calculation is
  /// finalized.
  ///
  /// The type of termination used depends on the one specified at the
  /// constructor.
  ///
  /// @return The length of the arithmetic codeword after termination, in
  /// bytes.
  int terminate() {
    switch (ttype) {
      case TERM_FULL:
        //sets the remaining bits of the last byte of the coded bits.
        int tempc = c + a;
        c = c | 0xFFFF;
        if (c >= tempc) {
          c = c - 0x8000;
        }

        int remainingBits = 27 - cT;

        // Flushes remainingBits
        do {
          c <<= cT;
          if (b != 0xFF) {
            remainingBits -= 8;
          } else {
            remainingBits -= 7;
          }
          byteOut();
        } while (remainingBits > 0);

        b |= (1 << (-remainingBits)) - 1;
        if (b == 0xFF) {
          // Delay 0xFF bytes
          delFF = true;
        } else {
          // Write delayed 0xFF bytes
          if (delFF) {
            out.write(0xFF);
            delFF = false;
            nrOfWrittenBytes++;
          }
          out.write(b);
          nrOfWrittenBytes++;
        }
        break;
      case TERM_PRED_ER:
      case TERM_EASY:
        // The predictable error resilient and easy termination are the
        // same, except for the fact that the easy one can modify the
        // spare bits in the last byte to maximize the likelihood of
        // having a 0xFF, while the error resilient one can not touch
        // these bits.

        // In the predictable error resilient case the spare bits will be
        // recalculated by the decoder and it will check if they are the
        // same as as in the codestream and then deduce an error
        // probability from there.

        int k; // number of bits to push out

        k = (11 - cT) + 1;

        c <<= cT;
        for (; k > 0; k -= cT, c <<= cT) {
          byteOut();
        }

        // Make any spare bits 1s if in easy termination
        if (k < 0 && ttype == TERM_EASY) {
          // At this stage there is never a carry bit in C, so we can
          // freely modify the (-k) least significant bits.
          b |= (1 << (-k)) - 1;
        }

        byteOut(); // Push contents of byte buffer
        break;
      case TERM_NEAR_OPT:

        // This algorithm terminates in the shortest possible way, besides
        // the fact any previous 0xFF 0x7F sequences are not
        // eliminated. The probabalility of having those sequences is
        // extremely low.

        // The calculation of the length is based on the fact that the
        // decoder will pad the codestream with an endless string of
        // (binary) 1s. If the codestream, padded with 1s, is within the
        // bounds of the current interval then correct decoding is
        // guaranteed. The lower inclusive bound of the current interval
        // is the value of C (i.e. if only lower intervals would be coded
        // in the future). The upper exclusive bound of the current
        // interval is C+A (i.e. if only upper intervals would be coded in
        // the future). We therefore calculate the minimum length that
        // would be needed so that padding with 1s gives a codestream
        // within the interval.

        // In general, such a calculation needs the value of the next byte
        // that appears in the codestream. Here, since we are terminating,
        // the next value can be anything we want that lies within the
        // interval, we use the lower bound since this minimizes the
        // length. To calculate the necessary length at any other place
        // than the termination it is necessary to know the next bytes
        // that will appear in the codestream, which involves storing the
        // codestream and the sate of the MQCoder at various points (a
        // worst case approach can be used, but it is much more
        // complicated and the calculated length would be only marginally
        // better than much simple calculations, if not the same).

        int cLow;
        int cUp;
        int bLow;
        int bUp;

        // Initialize the upper (exclusive) and lower bound (inclusive) of
        // the valid interval (the actual interval is the concatenation of
        // bUp and cUp, and bLow and cLow).
        cLow = c;
        cUp = c + a;
        bLow = bUp = b;

        // We start by normalizing the C register to the sate cT = 0
        // (i.e., just before byteOut() is called)
        cLow <<= cT;
        cUp <<= cT;
        // Progate eventual carry bits and reset them in Clow, Cup NOTE:
        // carry bit can never be set if the byte buffer was empty so no
        // problem with propagating a carry into an empty byte buffer.
        if ((cLow & (1 << 27)) != 0) {
          // Carry bit in cLow
          if (bLow == 0xFF) {
            // We can not propagate carry bit, do bit stuffing
            delFF = true; // delay 0xFF
            // Get next byte buffer
            bLow = cLow >>> 20;
            bUp = cUp >>> 20;
            cLow &= 0xFFFFF;
            cUp &= 0xFFFFF;
            // Normalize to cT = 0
            cLow <<= 7;
            cUp <<= 7;
          } else {
            // we can propagate carry bit
            bLow++; // propagate
            cLow &= ~(1 << 27); // reset carry in cLow
          }
        }
        if ((cUp & (1 << 27)) != 0) {
          bUp++; // propagate
          cUp &= ~(1 << 27); // reset carry
        }

        // From now on there can never be a carry bit on cLow, since we
        // always output bLow.

        // Loop testing for the condition and doing byte output if they
        // are not met.
        while (true) {
          // If decoder's codestream is within interval stop
          // If preceding byte is 0xFF only values [0,127] are valid
          if (delFF) {
            // If delayed 0xFF
            if (bLow <= 127 && bUp > 127) break;
            // We will write more bytes so output delayed 0xFF now
            out.write(0xFF);
            nrOfWrittenBytes++;
            delFF = false;
          } else {
            // No delayed 0xFF
            if (bLow <= 255 && bUp > 255) break;
          }

          // Output next byte
          // We could output anything within the interval, but using
          // bLow simplifies things a lot.

          // We should not have any carry bit here

          // Output bLow
          if (bLow < 255) {
            // Transfer byte bits from C to B
            // (if the byte buffer was empty output nothing)
            if (nrOfWrittenBytes >= 0) out.write(bLow);
            nrOfWrittenBytes++;
            bUp -= bLow;
            bUp <<= 8;
            // Here bLow would be 0
            bUp |= (cUp >>> 19) & 0xFF;
            bLow = (cLow >>> 19) & 0xFF;
            // Clear upper bits (just pushed out) from cUp Clow.
            cLow &= 0x7FFFF;
            cUp &= 0x7FFFF;
            // Goto next state where CT is 0
            cLow <<= 8;
            cUp <<= 8;
            // Here there can be no carry on Cup, Clow
          } else {
            // bLow = 0xFF
            // Transfer byte bits from C to B
            // Since the byte to output is 0xFF we can delay it
            delFF = true;
            bUp -= bLow;
            bUp <<= 7;
            // Here bLow would be 0
            bUp |= (cUp >> 20) & 0x7F;
            bLow = (cLow >> 20) & 0x7F;
            // Clear upper bits (just pushed out) from cUp Clow.
            cLow &= 0xFFFFF;
            cUp &= 0xFFFFF;
            // Goto next state where CT is 0
            cLow <<= 7;
            cUp <<= 7;
            // Here there can be no carry on Cup, Clow
          }
        }
        break;
      default:
        throw StateError("Illegal termination type code");
    }

    // Reinitialize the state (without modifying the contexts)
    int len;

    len = nrOfWrittenBytes;
    a = 0x8000;
    c = 0;
    b = 0;
    cT = 12;
    delFF = false;
    nrOfWrittenBytes = -1;

    // Return the terminated length
    return len;
  }

  /// Returns the number of contexts in the arithmetic coder.
  ///
  /// @return The number of contexts
  int getNumCtxts() {
    return I.length;
  }

  /// Resets a context to the original probability distribution, and sets its
  /// more probable symbol to 0.
  ///
  /// [c] The number of the context (it starts at 0).
  void resetCtxt(int c) {
    I[c] = initStates[c];
    mPS[c] = 0;
  }

  /// Resets all contexts to their original probability distribution and sets
  /// all more probable symbols to 0.
  void resetCtxts() {
    I.setRange(0, I.length, initStates);
    ArrayUtil.intArraySet(mPS, 0);
  }

  /// Returns the number of bytes that are necessary from the compressed
  /// output stream to decode all the symbols that have been coded this
  /// far. The number of returned bytes does not include anything coded
  /// previous to the last time the 'terminate()' or 'reset()' methods where
  /// called.
  ///
  /// The values returned by this method are then to be used in finishing
  /// the length calculation with the 'finishLengthCalculation()' method,
  /// after compensation of the offset in the number of bytes due to previous
  /// terminated segments.
  ///
  /// This method should not be called if the current coding pass is to be
  /// terminated. The 'terminate()' method should be called instead.
  ///
  /// The calculation is done based on the type of length calculation
  /// specified at the constructor.
  ///
  /// @return The number of bytes in the compressed output stream necessary
  /// to decode all the information coded this far.
  int getNumCodedBytes() {
    // NOTE: testing these algorithms for correctness is quite
    // difficult. One way is to modify the rate allocator so that not all
    // bit-planes are output if the distortion estimate for last passes is
    // the same as for the previous ones.

    switch (ltype) {
      case LENGTH_LAZY_GOOD:
        // This one is a bit better than LENGTH_LAZY.
        int bitsInN3Bytes; // The minimum amount of bits that can be
        // stored in the 3 bytes following the current byte buffer 'b'.

        if (b >= 0xFE) {
          // The byte after b can have a bit stuffed so ther could be
          // one less bit available
          bitsInN3Bytes = 22; // 7 + 8 + 7
        } else {
          // We are sure that next byte after current byte buffer has no
          // bit stuffing
          bitsInN3Bytes = 23; // 8 + 7 + 8
        }
        if ((11 - cT + 16) <= bitsInN3Bytes) {
          return nrOfWrittenBytes + (delFF ? 1 : 0) + 1 + 3;
        } else {
          return nrOfWrittenBytes + (delFF ? 1 : 0) + 1 + 4;
        }
      case LENGTH_LAZY:
        // This is the very basic one that appears in the VM text
        if ((27 - cT) <= 22) {
          return nrOfWrittenBytes + (delFF ? 1 : 0) + 1 + 3;
        } else {
          return nrOfWrittenBytes + (delFF ? 1 : 0) + 1 + 4;
        }
      case LENGTH_NEAR_OPT:
        // This is the best length calculation implemented in this class.
        // It is almost always optimal. In order to calculate the length
        // it is necessary to know which bytes will follow in the MQ
        // bit stream, so we need to wait until termination to perform it.
        // Save the state to perform the calculation later, in
        // finishLengthCalculation()
        saveState();
        // Return current number of output bytes to use it later in
        // finishLengthCalculation()
        return nrOfWrittenBytes;
      default:
        throw StateError("Illegal length calculation type code");
    }
  }

  /// Reinitializes the MQ coder and the underlying 'ByteOutputBuffer' buffer
  /// as if a new object was instantaited. All the data in the
  /// 'ByteOutputBuffer' buffer is erased and the state and contexts of the
  /// MQ coder are reinitialized). Additionally any saved MQ states are
  /// discarded.
  void reset() {
    // Reset the output buffer
    out.reset();

    a = 0x8000;
    c = 0;
    b = 0;
    if (b == 0xFF)
      cT = 13;
    else
      cT = 12;
    resetCtxts();
    nrOfWrittenBytes = -1;
    delFF = false;

    nSaved = 0;
  }

  /// Saves the current state of the MQ coder (just the registers, not the
  /// contexts) so that a near optimal length calculation can be performed
  /// later.
  void saveState() {
    // Increase capacity if necessary
    if (nSaved == savedC!.length) {
      List<int> tmp;
      tmp = savedC!;
      savedC = List<int>.filled(nSaved + SAVED_INC, 0);
      savedC!.setRange(0, nSaved, tmp);
      tmp = savedCT!;
      savedCT = List<int>.filled(nSaved + SAVED_INC, 0);
      savedCT!.setRange(0, nSaved, tmp);
      tmp = savedA!;
      savedA = List<int>.filled(nSaved + SAVED_INC, 0);
      savedA!.setRange(0, nSaved, tmp);
      tmp = savedB!;
      savedB = List<int>.filled(nSaved + SAVED_INC, 0);
      savedB!.setRange(0, nSaved, tmp);
      List<bool> tmpBool = savedDelFF!;
      savedDelFF = List<bool>.filled(nSaved + SAVED_INC, false);
      savedDelFF!.setRange(0, nSaved, tmpBool);
    }
    // Save the current sate
    savedC![nSaved] = c;
    savedCT![nSaved] = cT;
    savedA![nSaved] = a;
    savedB![nSaved] = b;
    savedDelFF![nSaved] = delFF;
    nSaved++;
  }

  /// Terminates the calculation of the required length for each coding
  /// pass. This method must be called just after the 'terminate()' one has
  /// been called for each terminated MQ segment.
  ///
  /// The values in 'rates' must have been compensated for any offset due
  /// to previous terminated segments, so that the correct index to the
  /// stored coded data is used.
  ///
  /// [rates] The array containing the values returned by
  /// 'getNumCodedBytes()' for each coding pass.
  ///
  /// [n] The index in the 'rates' array of the last terminated length.
  void finishLengthCalculation(List<int> rates, int n) {
    if (ltype != LENGTH_NEAR_OPT) {
      // For the simple calculations the only thing we need to do is to
      // ensure that the calculated lengths are no greater than the
      // terminated one
      if (n > 0 && rates[n - 1] > rates[n]) {
        // We need correction
        int tl = rates[n]; // The terminated length
        n--;
        do {
          rates[n--] = tl;
        } while (n >= 0 && rates[n] > tl);
      }
    } else {
      // We need to perform the more sophisticated near optimal
      // calculation.

      // The calculation of the length is based on the fact that the
      // decoder will pad the codestream with an endless string of
      // (binary) 1s after termination. If the codestream, padded with
      // 1s, is within the bounds of the current interval then correct
      // decoding is guaranteed. The lower inclusive bound of the
      // current interval is the value of C (i.e. if only lower
      // intervals would be coded in the future). The upper exclusive
      // bound of the current interval is C+A (i.e. if only upper
      // intervals would be coded in the future). We therefore calculate
      // the minimum length that would be needed so that padding with 1s
      // gives a codestream within the interval.

      // In order to know what will be appended to the current base of
      // the interval we need to know what is in the MQ bit stream after
      // the current last output byte until the termination. This is why
      // this calculation has to be performed after the MQ segment has
      // been entirely coded and terminated.

      int cLow; // lower bound on the C register for correct decoding
      int cUp; // upper bound on the C register for correct decoding
      int bLow; // lower bound on the byte buffer for correct decoding
      int bUp; // upper bound on the byte buffer for correct decoding
      int ridx; // index in the rates array of the pass we are
      // calculating
      int sidx; // index in the saved state array
      int clen; // current calculated length
      bool cdFF; // the current delayed FF state
      int nb; // the next byte of output
      int minlen; // minimum possible length
      int maxlen; // maximum possible length

      // Start on the first pass of this segment
      ridx = n - nSaved;
      // Minimum allowable length is length of previous termination
      minlen = (ridx - 1 >= 0) ? rates[ridx - 1] : 0;
      // Maximum possible length is the terminated length
      maxlen = rates[n];
      for (sidx = 0; ridx < n; ridx++, sidx++) {
        // Load the initial values of the bounds
        cLow = savedC![sidx];
        cUp = savedC![sidx] + savedA![sidx];
        bLow = savedB![sidx];
        bUp = savedB![sidx];
        // Normalize to cT=0 and propagate and reset any carry bits
        cLow <<= savedCT![sidx];
        if ((cLow & 0x8000000) != 0) {
          bLow++;
          cLow &= 0x7FFFFFF;
        }
        cUp <<= savedCT![sidx];
        if ((cUp & 0x8000000) != 0) {
          bUp++;
          cUp &= 0x7FFFFFF;
        }
        // Initialize current calculated length
        cdFF = savedDelFF![sidx];
        // rates[ridx] contains the number of bytes already output
        // when the state was saved, compensated for the offset in the
        // output stream.
        clen = rates[ridx] + (cdFF ? 1 : 0);
        while (true) {
          // If we are at end of coded data then this is the length
          if (clen >= maxlen) {
            clen = maxlen;
            break;
          }
          // Check for sufficiency of coded data
          if (cdFF) {
            if (bLow < 128 && bUp >= 128) {
              // We are done for this pass
              clen--; // Don't need delayed FF
              break;
            }
          } else {
            if (bLow < 256 && bUp >= 256) {
              // We are done for this pass
              break;
            }
          }
          // Update bounds with next byte of coded data and
          // normalize to cT = 0 again.
          nb = (clen >= minlen) ? out.getByte(clen) : 0;
          bLow -= nb;
          bUp -= nb;
          clen++;
          if (nb == 0xFF) {
            bLow <<= 7;
            bLow |= (cLow >> 20) & 0x7F;
            cLow &= 0xFFFFF;
            cLow <<= 7;
            bUp <<= 7;
            bUp |= (cUp >> 20) & 0x7F;
            cUp &= 0xFFFFF;
            cUp <<= 7;
            cdFF = true;
          } else {
            bLow <<= 8;
            bLow |= (cLow >> 19) & 0xFF;
            cLow &= 0x7FFFF;
            cLow <<= 8;
            bUp <<= 8;
            bUp |= (cUp >> 19) & 0xFF;
            cUp &= 0x7FFFF;
            cUp <<= 8;
            cdFF = false;
          }
          // Test again
        }
        // Store the rate found
        rates[ridx] = (clen >= minlen) ? clen : minlen;
      }
      // Reset the saved states
      nSaved = 0;
    }
  }
}

