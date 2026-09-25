// m2note ICU-53 ABI shim (pattern: vendor/mediatek/symbols/icu.cpp, the m681
// ICU-56 shim).
//
// The m2note blobs were linked against ICU 53 (versioned C exports, _53
// suffix); Pie ships ICU 60 (external/icu/icu4c/source/common/unicode/
// uvernum.h:61).  FACT (readelf --dyn-syms, 2026-09-25): /vendor/bin/mtk_agpsd
// has exactly these seven *_53 imports: ucnv_open, ucnv_close, ucnv_convertEx,
// ucnv_setFromUCallBack, ucnv_setToUCallBack, UCNV_FROM_U_CALLBACK_STOP,
// UCNV_TO_U_CALLBACK_STOP; libdrmmtkutil, libmzplayer and libtaglib add
// ucnv_toUnicode and ucnv_fromUChars.  The ucnv C API is U_STABLE since ICU 2.0
// with identical prototypes, so thin forwarders under the _53 names are
// ABI-safe; <unicode/ucnv.h> renames the unsuffixed calls to their _60 exports.
#include <unicode/ucnv.h>
#include <unicode/ucnv_err.h>

extern "C" {

UConverter* ucnv_open_53(const char* converterName, UErrorCode* err) {
  return ucnv_open(converterName, err);
}

void ucnv_close_53(UConverter* converter) {
  ucnv_close(converter);
}

void ucnv_convertEx_53(UConverter* targetCnv, UConverter* sourceCnv,
                       char** target, const char* targetLimit,
                       const char** source, const char* sourceLimit,
                       UChar* pivotStart, UChar** pivotSource,
                       UChar** pivotTarget, const UChar* pivotLimit,
                       UBool reset, UBool flush, UErrorCode* pErrorCode) {
  ucnv_convertEx(targetCnv, sourceCnv, target, targetLimit, source,
                 sourceLimit, pivotStart, pivotSource, pivotTarget, pivotLimit,
                 reset, flush, pErrorCode);
}

void ucnv_setFromUCallBack_53(UConverter* converter,
                              UConverterFromUCallback newAction,
                              const void* newContext,
                              UConverterFromUCallback* oldAction,
                              const void** oldContext, UErrorCode* err) {
  ucnv_setFromUCallBack(converter, newAction, newContext, oldAction,
                        oldContext, err);
}

void ucnv_setToUCallBack_53(UConverter* converter,
                            UConverterToUCallback newAction,
                            const void* newContext,
                            UConverterToUCallback* oldAction,
                            const void** oldContext, UErrorCode* err) {
  ucnv_setToUCallBack(converter, newAction, newContext, oldAction, oldContext,
                      err);
}

void ucnv_toUnicode_53(UConverter* converter, UChar** target,
                       const UChar* targetLimit, const char** source,
                       const char* sourceLimit, int32_t* offsets, UBool flush,
                       UErrorCode* err) {
  ucnv_toUnicode(converter, target, targetLimit, source, sourceLimit, offsets,
                 flush, err);
}

int32_t ucnv_fromUChars_53(UConverter* cnv, char* dest, int32_t destCapacity,
                           const UChar* src, int32_t srcLength,
                           UErrorCode* pErrorCode) {
  return ucnv_fromUChars(cnv, dest, destCapacity, src, srcLength, pErrorCode);
}

void UCNV_FROM_U_CALLBACK_STOP_53(const void* context,
                                  UConverterFromUnicodeArgs* fromUArgs,
                                  const UChar* codeUnits, int32_t length,
                                  UChar32 codePoint,
                                  UConverterCallbackReason reason,
                                  UErrorCode* err) {
  UCNV_FROM_U_CALLBACK_STOP(context, fromUArgs, codeUnits, length, codePoint,
                            reason, err);
}

void UCNV_TO_U_CALLBACK_STOP_53(const void* context,
                                UConverterToUnicodeArgs* toUArgs,
                                const char* codeUnits, int32_t length,
                                UConverterCallbackReason reason,
                                UErrorCode* err) {
  UCNV_TO_U_CALLBACK_STOP(context, toUArgs, codeUnits, length, reason, err);
}

}  // extern "C"
