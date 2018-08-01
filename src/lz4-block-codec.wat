;;
;; lz4-wasm - a WebAssembly implementation of LZ4 block format codec
;; Copyright (C) 2018 Raymond Hill
;;
;; BSD-2-Clause License (http://www.opensource.org/licenses/bsd-license.php)
;;
;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions are
;; met:
;; 
;;   1. Redistributions of source code must retain the above copyright
;; notice, this list of conditions and the following disclaimer.
;; 
;;   2. Redistributions in binary form must reproduce the above
;; copyright notice, this list of conditions and the following disclaimer
;; in the documentation and/or other materials provided with the
;; distribution.
;; 
;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;
;; Home: https://github.com/gorhill/lz4-wasm
;;
;; I used the same license as the one picked by creator of LZ4 out of respect
;; for his creation, see https://lz4.github.io/lz4/
;;

(module
;;
;; module start
;;

;; (func $log (import "imports" "log") (param i32 i32 i32))

(memory (export "memory") 1)

;;
;; Public functions
;;


;;
;; Return an offset to the first byte of usable linear memory.
;; Might be useful in the future to reserve memory space for whatever purpose,
;; like config variables, etc.
;;
(func $getLinearMemoryOffset (export "getLinearMemoryOffset") 
    (result i32)
    i32.const 0
)

;;
;; unsigned int lz4BlockEncodeBound()
;;
;; Return the maximum size of the output buffer holding the compressed data.
;;
;; Reference implementation:
;; https://github.com/lz4/lz4/blob/dev/lib/lz4.h#L156
;;
(func (export "lz4BlockEncodeBound")
    (param $ilen i32)
    (result i32)
    get_local $ilen
    i32.const 0x7E000000
    i32.gt_u
    if
        i32.const 0
        return
    end
    get_local $ilen
    get_local $ilen
    i32.const 255
    i32.div_u
    i32.add
    i32.const 16
    i32.add
)

;;
;; unsigned int lz4BlockEncode(unsigned int ilen)
;;
;; https://github.com/lz4/lz4/blob/dev/lib/lz4.c#L651
;;
;; The implementation below is modified from the reference one.
;; 
;; - There is no skip adjustement for repeated failure to find a match.
;; 
;; - All configurable values are hard-coded to match the generic version
;;   of the compressor.
;;
;; Note the size of the input block is NOT encoded in the output buffer, it
;; is for the caller to figure how they will save that information on
;; their side. At this point it is probably a trivial amount of work to
;; implement the LZ4 frame format, which encode the content size, but this
;; is for another day.
;;
(func (export "lz4BlockEncode")
    (param $ilen i32)                   ;; size of input buffer
    (result i32)
    (local $hashPtr0 i32)               ;; start of hash buffer
    (local $hashPtr i32)                ;; current hash entry
    (local $inPtr0 i32)                 ;; start of input buffer
    (local $anchorPtr i32)              ;; anchor position in input
    (local $inPtr i32)                  ;; current read position in input
    (local $inPtr1 i32)                 ;; point in input at which match-finding must cease
    (local $inPtr2 i32)                 ;; point in input at which match-length finding must cease
    (local $outPtr0 i32)                ;; start of output buffer
    (local $outPtr i32)                 ;; current write position in output
    (local $refPtr i32)                 ;; start of match in input
    (local $seq32 i32)                  ;; 4-byte value from current input position
    (local $llen i32)                   ;; length of found literals
    (local $moffset i32)                ;; offset to found match from current input position
    (local $mlen i32)                   ;; length of found match
    get_local $ilen
    i32.const 12
    i32.le_u
    if
        i32.const 0
        return
    end
    call $getLinearMemoryOffset         ;; unsigned char *hashPtr0 = &buffer[0];
    tee_local $hashPtr0
    i32.const 262144                    ;; hash table size * bytes per i32 = 65536 * 4
    i32.add
    tee_local $inPtr0
    tee_local $inPtr
    tee_local $anchorPtr
    get_local $ilen
    i32.add
    tee_local $outPtr0
    tee_local $outPtr
    i32.const -5                        ;; "The last 5 bytes are always literals."
    i32.add
    tee_local $inPtr2
    i32.const -7                        ;; "The last match must start at least 12 bytes before end of block"
    i32.add
    set_local $inPtr1
    block $sequence loop $findSequence
        get_local $inPtr
        get_local $inPtr1
        i32.ge_u
        br_if $sequence
        get_local $inPtr                ;; first sequence of 3 bytes before match-finding loop
        i32.load8_u
        i32.const 8
        i32.shl
        get_local $inPtr
        i32.load8_u offset=1
        i32.const 16
        i32.shl
        i32.or
        get_local $inPtr
        i32.load8_u offset=2
        i32.const 24
        i32.shl
        i32.or
        set_local $seq32
        block loop $findMatch           ;; match-finding loop
            get_local $inPtr
            get_local $inPtr2
            i32.ge_u
            br_if $sequence
            get_local $seq32            ;; update last byte of current sequence
            i32.const 8
            i32.shr_u
            get_local $inPtr
            i32.load8_u offset=3
            i32.const 24
            i32.shl
            i32.or
            tee_local $seq32
            i32.const 0x9E3779B1        ;; compute 16-bit hash
            i32.mul
            i32.const 16
            i32.shr_u                   ;; hash value is at top of stack
            i32.const 2                 ;; lookup refPtr at hash entry
            i32.shl
            get_local $hashPtr0
            i32.add
            tee_local $hashPtr
            i32.load
            set_local $refPtr
            get_local $hashPtr          ;; update hash entry with inPtr
            get_local $inPtr
            i32.store
            get_local $inPtr
            get_local $refPtr
            i32.sub
            tee_local $moffset          ;; remember match offset, we will need it in case of match
            i32.const 0xFFFF
            i32.gt_s
            if
                get_local $inPtr
                i32.const 1
                i32.add
                set_local $inPtr
                br $findMatch           ;; refPtr < 0 is = unused hash entry
            end
            ;; confirm match: different sequences can yield same hash
            ;; compare-branch each byte to potentially save memory read
            get_local $seq32            ;; byte 0
            i32.const 0xFF
            i32.and
            get_local $refPtr
            i32.load8_u
            i32.ne
            if
                get_local $inPtr
                i32.const 1
                i32.add
                set_local $inPtr
                br $findMatch           ;; refPtr[0] !== inPtr[0]
            end
            get_local $seq32            ;; byte 1
            i32.const 8
            i32.shr_u
            i32.const 0xFF
            i32.and
            get_local $refPtr
            i32.load8_u offset=1
            i32.ne
            if
                get_local $inPtr
                i32.const 1
                i32.add
                set_local $inPtr
                br $findMatch           ;; refPtr[1] !== inPtr[1]
            end
            get_local $seq32            ;; byte 2
            i32.const 16
            i32.shr_u
            i32.const 0xFF
            i32.and
            get_local $refPtr
            i32.load8_u offset=2
            i32.ne
            if
                get_local $inPtr
                i32.const 1
                i32.add
                set_local $inPtr
                br $findMatch           ;; refPtr[2] !== inPtr[2]
            end
            get_local $seq32            ;; byte 3
            i32.const 24
            i32.shr_u
            i32.const 0xFF
            i32.and
            get_local $refPtr
            i32.load8_u offset=3
            i32.ne
            if
                get_local $inPtr
                i32.const 1
                i32.add
                set_local $inPtr
                br $findMatch           ;; refPtr[3] !== inPtr[3]
            end
            ;;
            ;; a valid match has been found at this point
            ;;
            get_local $inPtr            ;; compute length of literals
            get_local $anchorPtr
            i32.sub
            set_local $llen
            get_local $inPtr            ;; find match length
            i32.const 4                 ;; skip over confirmed 4-byte match
            i32.add
            set_local $inPtr
            get_local $refPtr
            i32.const 4
            i32.add
            set_local $refPtr
            i32.const 0                 ;; scan input buffer until match ends
            set_local $mlen
            block $matchLengthFinder loop
                get_local $inPtr
                get_local $inPtr2
                i32.ge_u
                br_if $matchLengthFinder
                get_local $inPtr
                i32.load8_u
                get_local $refPtr
                i32.load8_u
                i32.ne
                br_if $matchLengthFinder
                get_local $inPtr
                i32.const 1
                i32.add
                set_local $inPtr
                get_local $refPtr
                i32.const 1
                i32.add
                set_local $refPtr
                get_local $mlen
                i32.const 1
                i32.add
                set_local $mlen
                br 0
            end end
            ;; encode token
            get_local $outPtr           ;; output token
            get_local $llen
            get_local $mlen
            call $writeToken
            get_local $outPtr
            i32.const 1
            i32.add
            set_local $outPtr
            get_local $llen             ;; encode/write length of literals if needed
            i32.const 15
            i32.ge_s
            if
                get_local $outPtr
                get_local $llen
                call $writeLength
                set_local $outPtr
            end
            ;; copy literals
            get_local $outPtr
            get_local $anchorPtr
            get_local $llen
            call $copy
            get_local $outPtr
            get_local $llen
            i32.add
            set_local $outPtr
            ;; encode match offset
            get_local $outPtr
            get_local $moffset
            i32.store8
            get_local $outPtr
            get_local $moffset
            i32.const 8
            i32.shr_u
            i32.store8 offset=1
            get_local $outPtr
            i32.const 2
            i32.add
            set_local $outPtr
            get_local $mlen             ;; encode/write length of match if needed
            i32.const 15
            i32.ge_s
            if
                get_local $outPtr
                get_local $mlen
                call $writeLength
                set_local $outPtr
            end
            get_local $inPtr            ;; advance anchor to current position
            set_local $anchorPtr
        end end
        br $findSequence
    end end
    ;;
    ;; generate last (match-less) sequence if compression succeeded
    ;;
    get_local $outPtr
    get_local $outPtr0
    i32.gt_u
    if
        get_local $outPtr
        get_local $outPtr0
        get_local $anchorPtr
        i32.sub
        tee_local $llen
        i32.const 0
        call $writeToken
        get_local $outPtr
        i32.const 1
        i32.add
        set_local $outPtr
        get_local $llen
        i32.const 15
        i32.ge_u
        if
            get_local $outPtr
            get_local $llen
            call $writeLength
            set_local $outPtr
        end
        get_local $outPtr
        get_local $anchorPtr
        get_local $llen
        call $copy
        get_local $outPtr
        get_local $llen
        i32.add
        set_local $outPtr
    end
    get_local $outPtr                   ;; return number of written bytes
    get_local $outPtr0
    i32.sub
)

;;
;; unsigned int lz4BlockDecode(unsigned int ilen)
;;
;; Reference:
;; https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
;;
(func (export "lz4BlockDecode")
    (param $ilen i32)
    (result i32)
    (local $inPtr0 i32)                 ;; start of input buffer
    (local $inPtr i32)                  ;; current position in input buffer
    (local $outPtr0 i32)                ;; start of output buffer
    (local $outPtr i32)                 ;; current position in output buffer
    (local $matchPtr i32)               ;; position of current match
    (local $token i32)                  ;; sequence token
    (local $clen i32)                   ;; number of bytes to copy 
    (local $_ i32)                      ;; general purpose variable
    get_local $ilen                     ;; if ( ilen == 0 ) { return 0; }
    i32.eqz
    if
        i32.const 0
        return
    end
    call $getLinearMemoryOffset
    tee_local $inPtr0                   ;; start of input buffer
    tee_local $inPtr                    ;; current position in input buffer
    get_local $ilen
    i32.add
    tee_local $outPtr0                  ;; start of output buffer
    set_local $outPtr                   ;; current position in output buffer
    block $sequence loop                ;; iterate through all sequences
        get_local $inPtr
        get_local $outPtr0
        i32.ge_u
        br_if $sequence                 ;; break when nothing left to read in input buffer
        get_local $inPtr                ;; read token -- consume one byte
        i32.load8_u
        get_local $inPtr
        i32.const 1
        i32.add
        set_local $inPtr
        tee_local $token                ;; extract length of literals from token
        i32.const 4
        i32.shr_u
        tee_local $clen                 ;; consume extra length bytes if present
        i32.eqz
        if else
            get_local $clen
            i32.const 15
            i32.eq
            if loop
                get_local $inPtr
                i32.load8_u
                get_local $inPtr
                i32.const 1
                i32.add
                set_local $inPtr
                tee_local $_
                get_local $clen
                i32.add
                set_local $clen
                get_local $_
                i32.const 255
                i32.eq
                br_if 0
            end end
            get_local $outPtr           ;; copy literals to ouput buffer
            get_local $inPtr
            get_local $clen
            call $copy
            get_local $outPtr           ;; advance output buffer pointer past copy
            get_local $clen
            i32.add
            set_local $outPtr
            get_local $clen             ;; advance input buffer pointer past literals
            get_local $inPtr
            i32.add
            tee_local $inPtr
            get_local $outPtr0          ;; exit if this is the last sequence
            i32.eq
            br_if $sequence
        end
        get_local $outPtr               ;; read match offset
        get_local $inPtr
        i32.load8_u
        get_local $inPtr
        i32.load8_u offset=1
        i32.const 8
        i32.shl
        i32.or
        i32.sub
        tee_local $matchPtr
        get_local $outPtr               ;; match position can't be outside input buffer bounds
        i32.eq
        br_if $sequence
        get_local $matchPtr
        get_local $outPtr0
        i32.lt_u
        br_if $sequence
        get_local $inPtr                ;; advance input pointer past match offset bytes
        i32.const 2
        i32.add
        set_local $inPtr
        get_local $token                ;; extract length of match from token
        i32.const 15
        i32.and
        i32.const 4
        i32.add
        tee_local $clen
        i32.const 19                    ;; consume extra length bytes if present
        i32.eq
        if loop
            get_local $inPtr
            i32.load8_u
            get_local $inPtr
            i32.const 1
            i32.add
            set_local $inPtr
            tee_local $_
            get_local $clen
            i32.add
            set_local $clen
            get_local $_
            i32.const 255
            i32.eq
            br_if 0
        end end
        get_local $outPtr               ;; copy match to ouput buffer
        get_local $matchPtr
        get_local $clen
        call $copy
        get_local $clen                 ;; advance output buffer pointer past copy
        get_local $outPtr
        i32.add
        set_local $outPtr
        br 0
    end end
    get_local $outPtr                   ;; return number of written bytes
    get_local $outPtr0
    i32.sub
)

;;
;; Private functions
;;

;;
;; Encode a sequence token
;;
;; Reference documentation:
;; https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
;;
(func $writeToken
    (param $outPtr i32)
    (param $llen i32)
    (param $mlen i32)
    get_local $outPtr
    get_local $llen
    i32.const 15
    i32.gt_u
    if
      i32.const 15
      set_local $llen
    end
    get_local $llen
    i32.const 4
    i32.shl
    get_local $mlen
    i32.const 15
    i32.gt_u
    if
      i32.const 15
      set_local $mlen
    end
    get_local $mlen
    i32.or
    i32.store8
)

;;
;; Encode and output length bytes. The return value is the pointer following
;; the last byte written.
;;
;; Reference documentation:
;; https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md
;;
(func $writeLength
    (param $outPtr i32)
    (param $len i32)
    (result i32)
    (local $_ i32)                      ;; general purpose short term temp var
    get_local $len
    i32.const 15
    i32.sub
    set_local $len
    loop
        get_local $len
        i32.const 255
        i32.gt_u
        if
            i32.const 255
            set_local $_
        else
            get_local $len
            set_local $_
        end
        get_local $outPtr
        get_local $_
        i32.store8
        get_local $outPtr
        i32.const 1
        i32.add
        set_local $outPtr
        get_local $len
        i32.const 255
        i32.sub
        tee_local $len
        i32.const 0
        i32.ge_s
        br_if 0
    end
    get_local $outPtr
)

;;
;; Copy n bytes from source to destination.
;;
;; It is overlap-safe only from left-to-right -- which is only what is
;; required in the current module.
;;
(func $copy
    (param $dst i32)
    (param $src i32)
    (param $len i32)
    block $copy8 loop
        get_local $len
        i32.const 8
        i32.lt_u
        br_if $copy8
        get_local $dst
        get_local $src
        i32.load8_u
        i32.store8
        get_local $dst
        get_local $src
        i32.load8_u offset=1
        i32.store8 offset=1
        get_local $dst
        get_local $src
        i32.load8_u offset=2
        i32.store8 offset=2
        get_local $dst
        get_local $src
        i32.load8_u offset=3
        i32.store8 offset=3
        get_local $dst
        get_local $src
        i32.load8_u offset=4
        i32.store8 offset=4
        get_local $dst
        get_local $src
        i32.load8_u offset=5
        i32.store8 offset=5
        get_local $dst
        get_local $src
        i32.load8_u offset=6
        i32.store8 offset=6
        get_local $dst
        get_local $src
        i32.load8_u offset=7
        i32.store8 offset=7
        get_local $dst
        i32.const 8
        i32.add
        set_local $dst
        get_local $src
        i32.const 8
        i32.add
        set_local $src
        get_local $len
        i32.const -8
        i32.add
        set_local $len
        br 0
    end end
    get_local $len
    i32.const 4
    i32.ge_u
    if
        get_local $dst
        get_local $src
        i32.load8_u
        i32.store8
        get_local $dst
        get_local $src
        i32.load8_u offset=1
        i32.store8 offset=1
        get_local $dst
        get_local $src
        i32.load8_u offset=2
        i32.store8 offset=2
        get_local $dst
        get_local $src
        i32.load8_u offset=3
        i32.store8 offset=3
        get_local $dst
        i32.const 4
        i32.add
        set_local $dst
        get_local $src
        i32.const 4
        i32.add
        set_local $src
        get_local $len
        i32.const -4
        i32.add
        set_local $len
    end
    get_local $len
    i32.const 2
    i32.ge_u
    if
        get_local $dst
        get_local $src
        i32.load8_u
        i32.store8
        get_local $dst
        get_local $src
        i32.load8_u offset=1
        i32.store8 offset=1
        get_local $dst
        i32.const 2
        i32.add
        set_local $dst
        get_local $src
        i32.const 2
        i32.add
        set_local $src
        get_local $len
        i32.const -2
        i32.add
        set_local $len
    end
    get_local $len
    i32.eqz
    if else
        get_local $dst
        get_local $src
        i32.load8_u
        i32.store8
    end
)

;;
;; module end
;;
)
