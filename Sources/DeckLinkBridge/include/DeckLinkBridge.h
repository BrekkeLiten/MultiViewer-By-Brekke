#ifndef METALMULTIVIEWER_DECKLINK_BRIDGE_H
#define METALMULTIVIEWER_DECKLINK_BRIDGE_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MVDeckLinkDriver MVDeckLinkDriver;

/// DeckLink capture devices supporting `IID_IDeckLinkInput` (indexed by `sdi:N`).
int32_t mvDeckLinkEnumerateDevices(void);

/// Caller must pass to `mvDeckLinkFreeString` when done (UTF-8, malloc’d).
char *mvDeckLinkCopyDeviceDisplayName(int32_t deviceIndex);
void mvDeckLinkFreeString(char *s);

MVDeckLinkDriver *mvDeckLinkDriverCreate(void);
void mvDeckLinkDriverRelease(MVDeckLinkDriver *driver);

/// Input index `deviceIndex`; uses Desktop Video routing (no forced connector in app).
bool mvDeckLinkDriverStart(MVDeckLinkDriver *driver, int32_t deviceIndex);
void mvDeckLinkDriverStop(MVDeckLinkDriver *driver);

/// After failed `mvDeckLinkDriverStart`, `HRESULT` as signed (e.g. `-1` if open failed).
void mvDeckLinkDriverGetLastStartFailure(int32_t *outStage, int32_t *outHRESULT);

typedef struct MVDeckLinkFramePacked {
	int32_t width;
	int32_t height;
	bool valid;
} MVDeckLinkFramePacked;

/// Copies the latest assembled **BGRA8** packed frame into `rgbaOut`; needs `capacityBytes >= width*height*4`.
bool mvDeckLinkDriverCopyLatestBGRAPacked(
	MVDeckLinkDriver *driver,
	uint8_t *rgbaOut,
	size_t capacityBytes,
	MVDeckLinkFramePacked *outInfo);

/// Lock-free dimension peek for sizing the Swift scratch buffer (`have` ⇒ at least one frame received).
bool mvDeckLinkDriverPeekDimensions(
	MVDeckLinkDriver *driver,
	int32_t *outWidth,
	int32_t *outHeight,
	bool *outHaveFrame);

#ifdef __cplusplus
}
#endif

#endif /* METALMULTIVIEWER_DECKLINK_BRIDGE_H */
