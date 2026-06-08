#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "DeckLinkBridge.h"

#include "DeckLinkAPI.h"
#include "DeckLinkAPIConfiguration.h"

#include <algorithm>
#include <atomic>
#include <cstring>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

static int32_t g_lastStartFailStage = 0;
static int32_t g_lastStartFailHR = 0;

static inline void MvRecordStartFail(HRESULT hr, int32_t stage) {
	g_lastStartFailStage = stage;
	g_lastStartFailHR = static_cast<int32_t>(hr);
}

#pragma mark - Global API lock

/// Iterator + device open are not safely used concurrently across threads.
static std::mutex gDeckLinkGlobalMutex;

#pragma mark - UYVY → BGRA8 (2vuy)

static inline uint8_t Clamp8(int v) {
	return (uint8_t)std::clamp(v, 0, 255);
}

/// One row: 2 pixels per UYVY macropixel; `width` is multiple of 2.
static void UYVYRowToBGRAPacked(const uint8_t *srcRow, int srcRowBytes, uint8_t *dstRow, int width) {
	for (int x = 0; x + 1 < width; x += 2) {
		const int o = (x / 2) * 4;
		if (o + 3 >= srcRowBytes)
			break;
		int u = int(srcRow[o + 0]) - 128;
		int y0 = int(srcRow[o + 1]);
		int v = int(srcRow[o + 2]) - 128;
		int y1 = int(srcRow[o + 3]);

		auto yuv_to_bgra = [](int yy, int uu, int vv, uint8_t *px) {
			int c = yy - 16;
			int d = uu;
			int e = vv;
			int r = int((298 * c + 409 * e + 128) >> 8);
			int g = int((298 * c - 100 * d - 208 * e + 128) >> 8);
			int b = int((298 * c + 516 * d + 128) >> 8);
			px[0] = Clamp8(b);
			px[1] = Clamp8(g);
			px[2] = Clamp8(r);
			px[3] = 255;
		};
		yuv_to_bgra(y0, u, v, dstRow + x * 4);
		yuv_to_bgra(y1, u, v, dstRow + (x + 1) * 4);
	}
}

#pragma mark - Device enumeration

static IDeckLinkIterator *CreateIteratorOrNull(void) {
	return CreateDeckLinkIteratorInstance();
}

static bool QueryInputInterface(IDeckLink *device, IDeckLinkInput **outInput) {
	*outInput = nullptr;
	if (!device)
		return false;
	return device->QueryInterface(IID_IDeckLinkInput, (void **) outInput) == S_OK && *outInput != nullptr;
}

/// `outUtf8Malloc` is `strdup` of UTF-8; caller frees.
static bool CopyDeckLinkUTF8Name(IDeckLink *device, char **outUtf8Malloc) {
	*outUtf8Malloc = nullptr;
	IDeckLinkProfileAttributes *attr = nullptr;
	if (device->QueryInterface(IID_IDeckLinkProfileAttributes, (void **) &attr) != S_OK || attr == nullptr) {
		return false;
	}
	CFStringRef name = nullptr;
	HRESULT hr = attr->GetString(BMDDeckLinkDisplayName, &name);
	attr->Release();
	if (hr != S_OK || name == nullptr)
		return false;

	CFIndex maxUtf8 =
		CFStringGetMaximumSizeForEncoding(CFStringGetLength(name), kCFStringEncodingUTF8) + 1;
	char *buf = (char *) malloc((size_t) maxUtf8);
	if (!buf) {
		CFRelease(name);
		return false;
	}
	if (!CFStringGetCString(name, buf, maxUtf8, kCFStringEncodingUTF8)) {
		free(buf);
		CFRelease(name);
		return false;
	}
	CFRelease(name);
	*outUtf8Malloc = buf;
	return true;
}

int32_t mvDeckLinkEnumerateDevices(void) {
	std::lock_guard<std::mutex> lk(gDeckLinkGlobalMutex);
	IDeckLinkIterator *it = CreateIteratorOrNull();
	if (!it)
		return 0;
	int32_t n = 0;
	while (true) {
		IDeckLink *dl = nullptr;
		HRESULT hr = it->Next(&dl);
		if (hr != S_OK || dl == nullptr)
			break;
		IDeckLinkInput *vin = nullptr;
		if (!QueryInputInterface(dl, &vin)) {
			dl->Release();
			continue;
		}
		vin->Release();
		n++;
		dl->Release();
	}
	it->Release();
	return n;
}

char *mvDeckLinkCopyDeviceDisplayName(int32_t deviceIndex) {
	if (deviceIndex < 0)
		return nullptr;
	std::lock_guard<std::mutex> lk(gDeckLinkGlobalMutex);
	IDeckLinkIterator *it = CreateIteratorOrNull();
	if (!it)
		return strdup("(DeckLink iterator unavailable — install Desktop Video)");
	int32_t ord = -1;
	char *out = nullptr;
	while (true) {
		IDeckLink *dl = nullptr;
		HRESULT hr = it->Next(&dl);
		if (hr != S_OK || dl == nullptr)
			break;
		IDeckLinkInput *vin = nullptr;
		if (!QueryInputInterface(dl, &vin)) {
			dl->Release();
			continue;
		}
		vin->Release();
		ord++;
		if (ord == deviceIndex) {
			char *nm = nullptr;
			if (!CopyDeckLinkUTF8Name(dl, &nm)) {
				nm = strdup("DeckLink input");
			}
			out = nm;
			dl->Release();
			break;
		}
		dl->Release();
	}
	it->Release();
	return out ? out : strdup("");
}

void mvDeckLinkFreeString(char *s) {
	free(s);
}

#pragma mark - Open device N

static bool OpenInputPairByOrdinal(int32_t wantOrdinal, IDeckLink **outDevice, IDeckLinkInput **outInput) {
	*outDevice = nullptr;
	*outInput = nullptr;
	IDeckLinkIterator *it = CreateIteratorOrNull();
	if (!it)
		return false;

	int32_t ord = -1;
	while (true) {
		IDeckLink *dl = nullptr;
		HRESULT hr = it->Next(&dl);
		if (hr != S_OK || dl == nullptr)
			break;
		IDeckLinkInput *vin = nullptr;
		if (!QueryInputInterface(dl, &vin)) {
			dl->Release();
			continue;
		}
		vin->Release();
		ord++;
		if (ord != wantOrdinal) {
			dl->Release();
			continue;
		}
		IDeckLinkInput *retInput = nullptr;
		if (dl->QueryInterface(IID_IDeckLinkInput, (void **) &retInput) != S_OK || retInput == nullptr) {
			dl->Release();
			break;
		}
		*outDevice = dl;
		*outInput = retInput;
		it->Release();
		return true;
	}
	it->Release();
	return false;
}

#pragma mark - Callback + driver

static BMDDisplayMode PickInitialDeckLinkInputMode(IDeckLinkInput *inp);

namespace {

class MVInputCallback final : public IDeckLinkInputCallback {
public:
	std::mutex frameMutex_;
	std::vector<uint8_t> packedBGRA_;
	int32_t lastW_ = 0;
	int32_t lastH_ = 0;
	bool haveFrame_ = false;
	std::atomic<bool> running_{ false };

	IDeckLinkInput *inputRef_ = nullptr;
	std::atomic<int32_t> refCount_{ 1 };

	/// Driver callback must return quickly; heavy unpack runs here. Queue holds at most one frame — newest wins (drops stale).
	std::mutex queueMtx_;
	std::condition_variable queueCv_;
	IDeckLinkVideoInputFrame *queuedFrame_ = nullptr;
	std::atomic<bool> workerStop_{ false };
	std::thread workerThread_;

	MVInputCallback(void) {}

	void startFrameWorker(void) {
		std::lock_guard<std::mutex> lk(queueMtx_);
		if (workerThread_.joinable())
			return;
		workerStop_.store(false, std::memory_order_release);
		workerThread_ = std::thread([this] { frameWorkerLoop(); });
	}

	void stopFrameWorker(void) {
		{
			std::lock_guard<std::mutex> lk(queueMtx_);
			workerStop_.store(true, std::memory_order_release);
		}
		queueCv_.notify_all();
		if (workerThread_.joinable())
			workerThread_.join();
		std::lock_guard<std::mutex> lk2(queueMtx_);
		if (queuedFrame_) {
			queuedFrame_->Release();
			queuedFrame_ = nullptr;
		}
		workerStop_.store(false, std::memory_order_release);
	}

	void frameWorkerLoop(void) {
		for (;;) {
			std::unique_lock<std::mutex> lk(queueMtx_);
			queueCv_.wait(lk, [&] {
				return queuedFrame_ != nullptr || workerStop_.load(std::memory_order_acquire);
			});
			if (workerStop_.load(std::memory_order_acquire)) {
				if (queuedFrame_) {
					queuedFrame_->Release();
					queuedFrame_ = nullptr;
				}
				break;
			}
			IDeckLinkVideoInputFrame *vf = queuedFrame_;
			queuedFrame_ = nullptr;
			lk.unlock();
			if (vf) {
				if (running_.load(std::memory_order_acquire))
					processQueuedVideoFrame(vf);
				vf->Release();
			}
		}
	}

	/// Runs on worker thread — may drop prior frames implicitly via single-slot queue.
	void processQueuedVideoFrame(IDeckLinkVideoInputFrame *videoFrame) {
		std::vector<uint8_t> next;
		int32_t w = 0, h = 0;
		void *pb = nullptr;
		BMDPixelFormat pix = videoFrame->GetPixelFormat();

		HRESULT gb = videoFrame->GetBytes(&pb);
		if (gb != S_OK || pb == nullptr)
			return;

		w = videoFrame->GetWidth();
		h = videoFrame->GetHeight();
		int rb = videoFrame->GetRowBytes();

		if (w <= 0 || h <= 0 || rb <= 0)
			return;

		next.resize(size_t(std::max(0, w * h * 4)));

		if (pix == bmdFormat8BitBGRA) {
			if (rb == w * 4) {
				std::memcpy(next.data(), pb, size_t(w) * size_t(h) * 4);
			} else {
				for (int y = 0; y < h; y++) {
					const uint8_t *src = reinterpret_cast<const uint8_t *>(pb) + y * rb;
					uint8_t *dst = next.data() + y * w * 4;
					std::memcpy(dst, src, size_t(std::min(w * 4, rb)));
				}
			}
		} else if (pix == bmdFormat8BitYUV) {
			if (w % 2 != 0)
				return;
			for (int y = 0; y < h; y++) {
				const uint8_t *sr = reinterpret_cast<const uint8_t *>(pb) + y * rb;
				uint8_t *dr = next.data() + y * w * 4;
				std::memset(dr, 0, size_t(w * 4));
				UYVYRowToBGRAPacked(sr, rb, dr, w);
			}
		} else {
			return;
		}

		{
			std::lock_guard<std::mutex> lk(frameMutex_);
			packedBGRA_.swap(next);
			lastW_ = w;
			lastH_ = h;
			haveFrame_ = true;
		}
	}

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *outPtr) override {
		if (!outPtr)
			return E_POINTER;
		CFUUIDBytes unkBytes = CFUUIDGetUUIDBytes(IUnknownUUID);
		REFIID iidUnk;
		std::memcpy(&iidUnk, &unkBytes, sizeof(REFIID));
		if (std::memcmp(&iid, &iidUnk, sizeof(REFIID)) == 0 ||
			std::memcmp(&iid, &IID_IDeckLinkInputCallback, sizeof(REFIID)) == 0) {
			*outPtr = static_cast<IDeckLinkInputCallback *>(this);
			AddRef();
			return S_OK;
		}
		*outPtr = nullptr;
		return E_NOINTERFACE;
	}

	ULONG STDMETHODCALLTYPE AddRef(void) override {
		int32_t n = refCount_.fetch_add(1, std::memory_order_relaxed) + 1;
		return static_cast<ULONG>(n > 0 ? n : 1);
	}

	ULONG STDMETHODCALLTYPE Release(void) override {
		int32_t v = refCount_.fetch_sub(1, std::memory_order_acq_rel) - 1;
		if (v == 0) {
			stopFrameWorker();
			delete this;
			return 0;
		}
		return (ULONG) v;
	}

	HRESULT STDMETHODCALLTYPE
	VideoInputFrameArrived(
		IDeckLinkVideoInputFrame *videoFrame,
		IDeckLinkAudioInputPacket *_Nullable audioPacket) override {

		if (audioPacket) { /* discard audio */
		}
		if (!videoFrame)
			return S_OK;
		if (!running_.load(std::memory_order_acquire))
			return S_OK;

		const uint32_t flags = videoFrame->GetFlags();
		if (flags & bmdFrameHasNoInputSource)
			return S_OK;

		videoFrame->AddRef();
		{
			std::lock_guard<std::mutex> qk(queueMtx_);
			if (queuedFrame_)
				queuedFrame_->Release();
			queuedFrame_ = videoFrame;
		}
		queueCv_.notify_one();
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE
	VideoInputFormatChanged(
		BMDVideoInputFormatChangedEvents events,
		IDeckLinkDisplayMode *nullableMode,
		BMDDetectedVideoInputFormatFlags) override {

		IDeckLinkInput *inp = inputRef_;
		if (!inp || !running_.load())
			return S_OK;

		/// Runtime evidence (`events==bmdVideoInputColorspaceChanged` storms): restarting capture with `bmdModeUnknown`
		/// here drops SDI lock. Only recycle the pipe when display mode actually changed.
		if (!(events & bmdVideoInputDisplayModeChanged))
			return S_OK;

		inp->PauseStreams();

		BMDDisplayMode dm = PickInitialDeckLinkInputMode(inp);
		if (nullableMode)
			dm = nullableMode->GetDisplayMode();

		const BMDVideoInputFlags detectFlags =
			(BMDVideoInputFlags) (bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection);
		/// Match startup: YUV first (quad / 8K paths often fail with BGRA-only here).
		HRESULT he = E_FAIL;
		for (BMDPixelFormat pix : { bmdFormat8BitYUV, bmdFormat8BitBGRA }) {
			he = inp->EnableVideoInput(dm, pix, detectFlags);
			if (SUCCEEDED(he))
				break;
		}
		if (FAILED(he))
			return S_OK;
		inp->FlushStreams();
		inp->StartStreams();
		return S_OK;
	}
};

/// Returns the profile UUID from SDK `activatedProfile` (fourcc per `enum _BMDProfileID`).
static BMDProfileID MvDeckLinkProfileIDFromProfile(IDeckLinkProfile *p) {
	if (!p)
		return 0;
	IDeckLinkProfileAttributes *attr = nullptr;
	if (FAILED(p->QueryInterface(IID_IDeckLinkProfileAttributes, (void **)&attr)) || attr == nullptr)
		return 0;
	int64_t v = 0;
	const HRESULT hr = attr->GetInt(BMDDeckLinkProfileID, &v);
	attr->Release();
	return SUCCEEDED(hr) ? static_cast<BMDProfileID>(v) : 0;
}

/// Completes DeckLink SDK profile handshake: activation is asynchronous until ProfileActivated fires.
class MVProfileActivationWait final : public IDeckLinkProfileCallback {
public:
	std::mutex mtx_;
	std::condition_variable cv_;
	bool activated_{ false };
	BMDProfileID expectedId_{ 0 };
	std::atomic<int32_t> refCount_{ 1 };

	MVProfileActivationWait() = default;

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *outPtr) override {
		if (!outPtr)
			return E_POINTER;
		CFUUIDBytes unkBytes = CFUUIDGetUUIDBytes(IUnknownUUID);
		REFIID iidUnk;
		std::memcpy(&iidUnk, &unkBytes, sizeof(REFIID));
		if (std::memcmp(&iid, &iidUnk, sizeof(REFIID)) == 0 ||
			std::memcmp(&iid, &IID_IDeckLinkProfileCallback, sizeof(REFIID)) == 0) {
			*outPtr = static_cast<IDeckLinkProfileCallback *>(this);
			AddRef();
			return S_OK;
		}
		*outPtr = nullptr;
		return E_NOINTERFACE;
	}

	ULONG STDMETHODCALLTYPE AddRef(void) override {
		int32_t n = refCount_.fetch_add(1, std::memory_order_relaxed) + 1;
		return static_cast<ULONG>(n > 0 ? n : 1);
	}

	ULONG STDMETHODCALLTYPE Release(void) override {
		int32_t v = refCount_.fetch_sub(1, std::memory_order_acq_rel) - 1;
		if (v == 0) {
			delete this;
			return 0;
		}
		return (ULONG) v;
	}

	HRESULT STDMETHODCALLTYPE ProfileChanging(IDeckLinkProfile * /*profileToBeActivated*/,
		bool /*streamsWillBeForcedToStop*/) override {
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE ProfileActivated(IDeckLinkProfile *activatedProfile) override {
		const BMDProfileID got = MvDeckLinkProfileIDFromProfile(activatedProfile);
		bool match = false;
		{
			std::lock_guard<std::mutex> lk(mtx_);
			match = (expectedId_ != 0 && got == expectedId_);
			if (match)
				activated_ = true;
		}
		cv_.notify_all();
		return S_OK;
	}

	/// Begins waiting for ProfileActivated carrying the same profile id as passed to SetActive.
	void prepareExpecting(BMDProfileID expect) {
		std::lock_guard<std::mutex> lk(mtx_);
		expectedId_ = expect;
		activated_ = false;
	}

	bool waitActivatedForMilliseconds(int timeoutMs) {
		std::unique_lock<std::mutex> lk(mtx_);
		return cv_.wait_for(lk, std::chrono::milliseconds(timeoutMs), [this] { return activated_; });
	}
};

} // namespace

struct MVDeckLinkDriver {
	IDeckLink *device = nullptr;
	IDeckLinkInput *input = nullptr;
	IDeckLinkConfiguration *config = nullptr;
	MVInputCallback *callback = nullptr;
};

MVDeckLinkDriver *mvDeckLinkDriverCreate(void) {
	auto *d = new (std::nothrow) MVDeckLinkDriver();
	return d;
}

void mvDeckLinkDriverRelease(MVDeckLinkDriver *driver) {
	if (!driver)
		return;
	mvDeckLinkDriverStop(driver);
	delete driver;
}

static void MvDeckLinkStopUnlocked(MVDeckLinkDriver *driver) {
	if (!driver)
		return;
	if (driver->callback) {
		driver->callback->running_.store(false, std::memory_order_release);
		driver->callback->stopFrameWorker();
	}
	if (driver->input && driver->callback) {
		driver->input->SetCallback(nullptr);
		driver->input->StopStreams();
		driver->input->DisableVideoInput();
	}
	if (driver->callback) {
		driver->callback->Release();
		driver->callback = nullptr;
	}
	if (driver->config) {
		driver->config->Release();
		driver->config = nullptr;
	}
	if (driver->input) {
		driver->input->Release();
		driver->input = nullptr;
	}
	if (driver->device) {
		driver->device->Release();
		driver->device = nullptr;
	}
}

void mvDeckLinkDriverStop(MVDeckLinkDriver *driver) {
	std::lock_guard<std::mutex> lk(gDeckLinkGlobalMutex);
	MvDeckLinkStopUnlocked(driver);
}

/// All input modes at least ~720p-class, **largest frame area first** (so UHD/8K precede 1080p when present).
static void AppendDeckLinkInputModesByDescendingArea(IDeckLinkInput *inp, std::vector<BMDDisplayMode> &candidates) {
	auto addUnique = [&](BMDDisplayMode m) {
		for (auto e : candidates) {
			if (e == m)
				return;
		}
		candidates.push_back(m);
	};

	struct ModeArea {
		BMDDisplayMode md;
		long area;
	};
	std::vector<ModeArea> scraped;

	if (inp) {
		IDeckLinkDisplayModeIterator *it = nullptr;
		if (SUCCEEDED(inp->GetDisplayModeIterator(&it)) && it != nullptr) {
			IDeckLinkDisplayMode *dm = nullptr;
			while (it->Next(&dm) == S_OK && dm != nullptr) {
				const long w = dm->GetWidth();
				const long h = dm->GetHeight();
				const BMDDisplayMode md = dm->GetDisplayMode();
				dm->Release();
				dm = nullptr;
				// Minimum ~720p horizontal width; avoids locking SD/EDL paths before format detect.
				if (w < 1280 || h < 720)
					continue;
				const long area = (w <= 0 || h <= 0) ? -1 : w * h;
				if (area > 0)
					scraped.push_back({ md, area });
			}
			it->Release();
		}
	}

	std::sort(scraped.begin(), scraped.end(), [](const ModeArea &a, const ModeArea &b) {
		if (a.area != b.area)
			return a.area > b.area;
		return (uint32_t) a.md > (uint32_t) b.md;
	});

	for (const auto &s : scraped)
		addUnique(s.md);
}

/// SDK \"Automatic Mode Detection\" requires a concrete initial mode + format detection flag (not `bmdModeUnknown`).
static BMDDisplayMode PickInitialDeckLinkInputMode(IDeckLinkInput *inp) {
	static const BMDDisplayMode kFallback = bmdModeHD1080p6000;
	if (!inp)
		return kFallback;

	std::vector<BMDDisplayMode> v;
	AppendDeckLinkInputModesByDescendingArea(inp, v);
	return v.empty() ? kFallback : v[0];
}

/// 8K Pro / Quad variants: switching to multi-input profiles can be required before `EnableVideoInput` succeeds (SDK §2.4.11).
/// Re-resolve `IID_IDeckLinkInput` after attempted activation — sub-device interfaces may change.
static bool ActivateDeckLinkCaptureProfileAndRefreshInput(IDeckLink *dev, IDeckLinkInput **inOutInput) {
	if (!dev || !inOutInput || !*inOutInput)
		return false;

	IDeckLinkProfileManager *mgr = nullptr;
	if (FAILED(dev->QueryInterface(IID_IDeckLinkProfileManager, (void **) &mgr)) || mgr == nullptr)
		return true;

	MVProfileActivationWait *waiter = new (std::nothrow) MVProfileActivationWait();
	if (!waiter) {
		mgr->Release();
		return true;
	}

	const HRESULT cbHR = mgr->SetCallback(waiter);
	if (FAILED(cbHR)) {
		waiter->Release();
		mgr->Release();
		return true;
	}

	static const struct {
		BMDProfileID id;
		const char *tag;
	} kProfiles[] = {
		{ bmdProfileFourSubDevicesHalfDuplex, "4dhd" },
		{ bmdProfileTwoSubDevicesFullDuplex, "2dfd" },
		{ bmdProfileTwoSubDevicesHalfDuplex, "2dhd" },
		{ bmdProfileOneSubDeviceFullDuplex, "1dfd" },
		{ bmdProfileOneSubDeviceHalfDuplex, "1dhd" },
	};

	const char *used = nullptr;
	for (const auto &pr : kProfiles) {
		IDeckLinkProfile *prof = nullptr;
		if (FAILED(mgr->GetProfile(pr.id, &prof)) || prof == nullptr)
			continue;
		waiter->prepareExpecting(pr.id);
		const HRESULT setHR = prof->SetActive();
		prof->Release();
		if (FAILED(setHR))
			continue;

		/// Quad handshake often completes just after shorter windows; premature fallback selects the wrong connector map → `skip_no_signal` forever.
		const int waitMs =
			(pr.id == bmdProfileFourSubDevicesHalfDuplex) ? 20000 : 8000;
		if (waiter->waitActivatedForMilliseconds(waitMs)) {
			used = pr.tag;
			break;
		}
	}

	mgr->SetCallback(nullptr);
	waiter->Release();

	mgr->Release();

	if (used == nullptr) {
		// ProfileManager existed but nothing was activated — keep existing IDeckLinkInput.
		return true;
	}

	(*inOutInput)->Release();
	*inOutInput = nullptr;

	const HRESULT iq = dev->QueryInterface(IID_IDeckLinkInput, (void **) inOutInput);
	if (FAILED(iq) || *inOutInput == nullptr)
		return false;
	return true;
}

/// Prefer modes reported by \c DoesSupportVideoMode with \c bmdSupportedVideoModeInAnyProfile before calling \c EnableVideoInput.
static HRESULT TryEnableDeckLinkVideoInput(
	IDeckLinkInput *inp,
	BMDDisplayMode *outEnabledMode,
	BMDPixelFormat *outEnabledPix) {

	if (!outEnabledMode || !outEnabledPix)
		return E_POINTER;
	*outEnabledMode = bmdModeUnknown;
	*outEnabledPix = bmdFormatUnspecified;

	const BMDVideoInputFlags detectFlags =
		(BMDVideoInputFlags) (bmdVideoInputFlagDefault | bmdVideoInputEnableFormatDetection);
	const BMDSupportedVideoModeFlags smf =
		(BMDSupportedVideoModeFlags) (bmdSupportedVideoModeDefault | bmdSupportedVideoModeInAnyProfile);

	std::vector<BMDDisplayMode> candidates;
	auto addUnique = [&](BMDDisplayMode m) {
		for (auto e : candidates) {
			if (e == m)
				return;
		}
		candidates.push_back(m);
	};

	AppendDeckLinkInputModesByDescendingArea(inp, candidates);

	/// Explicit fallbacks — some drivers list few iterator entries; insert UHD/DCI/8K *after* real sorted picks without reordering earlier tries.
	static const BMDDisplayMode kFallbackModes[] = {
		bmdMode8kDCI60,   bmdMode8kDCI5994, bmdMode8kDCI50,   bmdMode8kDCI48,  bmdMode8kDCI4795,
		bmdMode8kDCI30,   bmdMode8kDCI2997, bmdMode8kDCI25,   bmdMode8kDCI24,  bmdMode8kDCI2398,
		bmdMode8K4320p60, bmdMode8K4320p5994, bmdMode8K4320p50, bmdMode8K4320p4795, bmdMode8K4320p48,
		bmdMode8K4320p2997, bmdMode8K4320p30, bmdMode8K4320p25, bmdMode8K4320p24, bmdMode8K4320p2398,
		bmdMode4kDCI60,   bmdMode4kDCI5994, bmdMode4kDCI50,   bmdMode4kDCI48,  bmdMode4kDCI4795,
		bmdMode4kDCI30,   bmdMode4kDCI2997, bmdMode4kDCI25,   bmdMode4kDCI24,  bmdMode4kDCI2398,
		bmdMode4K2160p60, bmdMode4K2160p5994, bmdMode4K2160p50, bmdMode4K2160p4795, bmdMode4K2160p48,
		bmdMode4K2160p2997, bmdMode4K2160p30, bmdMode4K2160p25, bmdMode4K2160p24, bmdMode4K2160p2398,
		bmdModeHD1080p6000, bmdModeHD1080p5994, bmdModeHD1080p50,
		bmdModeHD720p60,
	};
	for (BMDDisplayMode m : kFallbackModes)
		addUnique(m);

	/// YUV first: some quad / multi-profile combos accept BGRA in `EnableVideoInput` yet only deliver usable SDI locks on `bmdFormat8BitYUV` (see NDJSON runs with BGRA + perpetual `skip_no_signal`).
	const BMDPixelFormat px[] = { bmdFormat8BitYUV, bmdFormat8BitBGRA };

	HRESULT lastHen = E_FAIL;
	for (BMDDisplayMode cand : candidates) {
		for (BMDPixelFormat pix : px) {
			BMDDisplayMode actual = cand;
			bool supported = false;
			const HRESULT dsm = inp->DoesSupportVideoMode(
				bmdVideoConnectionUnspecified,
				cand,
				pix,
				bmdNoVideoInputConversion,
				smf,
				&actual,
				&supported);

			BMDDisplayMode use = cand;
			if (dsm == S_OK && supported)
				use = actual;

			if (dsm == S_OK && !supported)
				continue;

			const HRESULT hen = inp->EnableVideoInput(use, pix, detectFlags);
			lastHen = hen;
			if (SUCCEEDED(hen)) {
				*outEnabledMode = use;
				*outEnabledPix = pix;
				return hen;
			}
		}
	}

	// Fallback: firmware sometimes mis-reports DoesSupportVideoMode — try Enables without DSM pre-check.
	for (BMDDisplayMode cand : candidates) {
		for (BMDPixelFormat pix : px) {
			const HRESULT hen = inp->EnableVideoInput(cand, pix, detectFlags);
			lastHen = hen;
			if (SUCCEEDED(hen)) {
				*outEnabledMode = cand;
				*outEnabledPix = pix;
				return hen;
			}
		}
	}

	return lastHen;
}

bool mvDeckLinkDriverStart(MVDeckLinkDriver *driver, int32_t deviceIndex) {
	if (!driver || deviceIndex < 0)
		return false;
	std::lock_guard<std::mutex> lk(gDeckLinkGlobalMutex);
	g_lastStartFailStage = 0;
	g_lastStartFailHR = 0;
	MvDeckLinkStopUnlocked(driver);

	IDeckLink *dev = nullptr;
	IDeckLinkInput *inp = nullptr;
	if (!OpenInputPairByOrdinal(deviceIndex, &dev, &inp)) {
		MvRecordStartFail(static_cast<HRESULT>(E_FAIL), 1);
		return false;
	}

	// Do not force `bmdDeckLinkConfigVideoInputConnection` here: 8K Pro / Desktop Video routing may
	// use HDMI, optical, or per-BNC profiles; forcing SDI breaks `EnableVideoInput` on some setups.

	auto *cb = new MVInputCallback();
	cb->running_.store(true, std::memory_order_release);

	if (!ActivateDeckLinkCaptureProfileAndRefreshInput(dev, &inp)) {
		MvRecordStartFail(static_cast<HRESULT>(E_FAIL), 2);
		cb->running_.store(false);
		cb->Release();
		dev->Release();
		return false;
	}
	cb->inputRef_ = inp;

	(void) inp->DisableVideoInput();

	// DeckLink requires the input callback BEFORE EnableVideoInput; otherwise Enable returns E_INVALIDARG-style HRESULTs (e.g. 0x80000003).
	HRESULT hs = inp->SetCallback(cb);
	if (FAILED(hs)) {
		MvRecordStartFail(hs, 4);
		cb->running_.store(false);
		cb->Release();
		inp->Release();
		dev->Release();
		return false;
	}

	cb->startFrameWorker();

	BMDDisplayMode enabledMode = bmdModeUnknown;
	BMDPixelFormat enabledPix = bmdFormatUnspecified;
	const HRESULT hen = TryEnableDeckLinkVideoInput(inp, &enabledMode, &enabledPix);
	if (FAILED(hen)) {
		MvRecordStartFail(hen, 3);
		cb->stopFrameWorker();
		inp->SetCallback(nullptr);
		cb->running_.store(false);
		cb->Release();
		inp->Release();
		dev->Release();
		return false;
	}

	HRESULT hc = inp->StartStreams();
	if (FAILED(hc)) {
		MvRecordStartFail(hc, 5);
		cb->stopFrameWorker();
		inp->SetCallback(nullptr);
		inp->DisableVideoInput();
		cb->running_.store(false);
		cb->Release();
		driver->callback = nullptr;
		inp->Release();
		dev->Release();
		return false;
	}

	driver->device = dev;
	driver->input = inp;
	driver->config = nullptr;
	driver->callback = cb;
	return true;
}

void mvDeckLinkDriverGetLastStartFailure(int32_t *outStage, int32_t *outHRESULT) {
	if (outStage)
		*outStage = g_lastStartFailStage;
	if (outHRESULT)
		*outHRESULT = g_lastStartFailHR;
}

bool mvDeckLinkDriverPeekDimensions(
	MVDeckLinkDriver *driver,
	int32_t *outWidth,
	int32_t *outHeight,
	bool *outHaveFrame) {

	if (!driver || !outWidth || !outHeight || !outHaveFrame || !driver->callback) {
		return false;
	}
	MVInputCallback *cb = driver->callback;
	std::lock_guard<std::mutex> lk(cb->frameMutex_);
	*outWidth = cb->lastW_;
	*outHeight = cb->lastH_;
	*outHaveFrame = cb->haveFrame_;
	return true;
}

bool mvDeckLinkDriverCopyLatestBGRAPacked(
	MVDeckLinkDriver *driver,
	uint8_t *rgbaOut,
	size_t capacityBytes,
	MVDeckLinkFramePacked *outInfo) {

	if (!driver || !rgbaOut || !outInfo || !driver->callback) {
		outInfo->valid = false;
		return false;
	}
	MVInputCallback *cb = driver->callback;
	std::lock_guard<std::mutex> lk(cb->frameMutex_);

	outInfo->width = cb->lastW_;
	outInfo->height = cb->lastH_;
	outInfo->valid = cb->haveFrame_ && cb->lastW_ > 0 && cb->lastH_ > 0;
	if (!outInfo->valid)
		return false;

	size_t need = size_t(cb->lastW_) * size_t(cb->lastH_) * 4;
	if (capacityBytes < need || cb->packedBGRA_.size() < need) {
		outInfo->valid = false;
		return false;
	}
	std::memcpy(rgbaOut, cb->packedBGRA_.data(), need);
	return true;
}
