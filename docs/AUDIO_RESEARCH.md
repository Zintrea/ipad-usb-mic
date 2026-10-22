# Audio Research: Making Speech, Singing + Guitar, and Saw Duang / Violin Sound Better

Reference for tuning the iPad mic app's DSP chain. Researched 2026-10-22.
Audience: Claude (and humans) changing `ios/IpadMic/` DSP code. Read this before changing EQ,
noise reduction, reverb, limiter, or adding dynamics.

**How to read the numbers.** Almost every value below is a *starting point*, not a rule. Each claim is
tagged:
- **[S]** = sourced (see Sources, numbered)
- **[C]** = consensus across several mixing guides (blogs/forums, not lab data)
- **[I]** = my inference / engineering judgment, not directly sourced
- **[U]** = unverified, needs on-device measurement

Current app chain (from `MicServer.swift`, since 2026-10-23): `noise reducer -> gain -> low-cut HPF -> mud peak (300 Hz) -> presence peak (2.5-5 kHz) -> high-cut LPF -> compressor (soft knee) -> reverb (Freeverb room/hall, pre-delay, wet HPF 180 Hz) -> lookahead limiter (1 ms, per-source release, -1 dBFS ceiling)`, Float32 mono 48 kHz. Per-source defaults (section 7) live in `Tones.swift`.

---

## 1. Physics primer (why the numbers are what they are)

### 1.1 Frequency bands and what they sound like [C]
| Band | Perceived as | Typical problem |
|---|---|---|
| < 60-80 Hz | rumble, handling, HVAC, table thumps | wastes headroom, triggers limiter for no audible gain |
| 100-250 Hz | warmth, body, voice/guitar fundamentals | boom, proximity effect |
| 200-500 Hz | "mud", "boxiness" | small rooms build up here; cut usually helps clarity more than any boost [S1][S2] |
| 800 Hz-1.8 kHz | nasal, honky | violin "nasal" region 1-1.8 kHz [S6][S7] |
| 2-5 kHz | presence, intelligibility, bite; ear most sensitive here | harshness, shrillness, string squeak |
| 5-10 kHz | sibilance ("s", "sh"), bow/pick detail | sibilance, hiss |
| > 10 kHz | "air", sheen | hiss, built-in mic noise |

The ear is most sensitive around 2-5 kHz (equal-loudness contours), so +/-1-2 dB here is very audible;
boosts here also raise noise and harshness fastest. [I]

### 1.2 Speaking voice
- Fundamental (F0): adult male ~85-180 Hz, female ~165-255 Hz (standard phonetics figures). [I]
- Intelligibility lives in consonants at ~1-4 kHz; a forum source cites ~2.5-3.5 kHz as the "legibility" region. [S10]
- Sibilance: ~5-10 kHz, varies by person. [S1][S12]

### 1.3 Singing voice
- **Singer's formant**: trained (mostly classical male) singers produce a spectral peak around
  **2.5-3 kHz** (range reported 2.4-3.6 kHz), caused by clustering of vocal-tract formants F3-F5. It
  lets a voice cut through an orchestra without extra loudness. Level varies with vowel, loudness,
  training. [S13][S14]
- Implication: a gentle presence lift in **2.5-3.5 kHz** mimics this "ring"; untrained / pop voices
  benefit more than classical ones (they lack it). [I]
- Pop/untrained voices: presence often quoted 3-5 or 3-6 kHz, +1-3 dB. [S1][S2]

### 1.4 Acoustic guitar
- Lowest string E2 = 82 Hz. Voice fundamentals start ~100-200 Hz, so a combined voice+guitar take
  can high-pass at ~70-80 Hz without losing the guitar's low E. [S8][S9]
- Body ~100-200 Hz (boom if close to the soundhole), boxiness ~400 Hz and ~1.5 kHz, pick sparkle 3-5 kHz,
  air ~12 kHz. [S8][S9]
- String squeak / fret noise: often ~2-5 kHz (one report: ~2.5 kHz). Best handled by mic distance or a
  dynamic cut, not static EQ (static EQ dulls the guitar). [S16]

### 1.5 Violin (proxy for saw duang where data is missing)
Established acoustics (Schleske, Jansson, Curtin):
- **~270-280 Hz**: Helmholtz / f-hole air resonance (A0). Not "mud" -- this is the instrument's low body. [S6][S7]
- **~400-600 Hz**: main corpus (body) resonances, "P1/P2" 400-500 / 500-600 Hz. [S6][S15]
- **1-1.8 kHz**: "nasal" range. Good violins are up to 10 dB *lower* here than in other strong regions. [S7]
- **2-3 kHz "bridge hill"**: a broad smooth hump (~2.5 kHz in Italian violins). It is perceptually
  important: stronger hill = softer/brilliant, weaker = sharper. [S15]
- **> ~6 kHz**: many strong resonances here make notes sound harsh. [S6]
- Mixing guides: tame shrillness around ~2 kHz and ~5 kHz by ear. [S6]

### 1.6 Saw duang (ซอด้วง)
What is sourced:
- Two-string Thai bowed spike fiddle. Hollow cylindrical body (hardwood or ivory; name refers to a
  bamboo-joint animal trap shape) with **snakeskin membrane** as soundboard. Bow hair passes *between*
  the two strings. Strings traditionally silk, now nylon or brass. [S17][S18]
- Sound: **high, bright, clear**; it leads the string ensemble. Contrast: saw u is mellow. [S17]
- Thai melodies on saw duang mostly use the "sol" mode; Thai tuning is nominally 7-tone near-equal
  (~171 cents/step) but measured tunings vary by school and player. [S19][S20]

What is NOT sourced (no acoustic measurement of saw duang found):
- Exact string pitches. Commonly taught as "sol-re" (Thai pitch names, roughly a 5th apart, high
  register) -- **[U]** verify by measuring the app's own recordings (e.g., FFT peak of open strings).
- Spectrum. Closest studied relative is the **erhu** (also a snakeskin-membrane cylindrical spike
  fiddle): the air-membrane resonance sits well below the cylinder's quarter-wave resonance; the
  membrane's lowest mode is ~2 octaves above that air resonance; the main response spans about
  1x-4.6x the air-resonance frequency. Student summary cites the lowest membrane mode near ~2 kHz. [S21][S22]
- Inference for saw duang **[I]**: expect (a) little useful energy below ~250-300 Hz (small body, high
  register) -> HPF can sit higher than for voice; (b) a strong membrane-driven region roughly 1-3 kHz
  that gives the "bright/nasal" Thai character -- do **not** cut it like a violin "nasal" problem,
  it is the instrument's identity; (c) bow noise and rosin scratch above ~5 kHz, plus snakeskin
  "buzz" that can be harsh at close distance.

---

## 2. EQ recommendations per source

Filter types available now: `Biquad.setHighPass(freq, q)` and `Biquad.setPeaking(freq, gainDB, q)`
(RBJ cookbook, 12 dB/oct HPF). A shelf would need a new `setHighShelf` (RBJ cookbook has it).

### 2.1 Speech
| Move | Value | Tag |
|---|---|---|
| HPF | 80 Hz (deep voice) to 100-120 Hz (higher voice), 12 dB/oct or steeper | [S1][S11] |
| Mud cut | -2 to -4 dB at 200-500 Hz, Q ~1-1.5, only if room is boomy | [S2] |
| Presence | +1 to +3 dB at 3-5 kHz | [S1] |
| Sibilance | de-ess 5-10 kHz rather than cutting statically | [S1][S12] |
| Air | +1-2 dB shelf above 10-12 kHz (only if mic noise allows) | [S1] |

### 2.2 Singing + acoustic guitar (single mic, one mono track)
| Move | Value | Tag |
|---|---|---|
| HPF | **70-80 Hz** (keep guitar low E at 82 Hz) | [S8][S9] |
| Warmth | optional +1-2 dB ~150 Hz (boomy if overdone) | [S8] |
| Mud | -2 dB ~250-400 Hz | [S8][S9] |
| Boxiness | -1 to -2 dB ~1.5 kHz (also prevents nasal voice) | [S8] |
| Presence | +1-2 dB 2.5-3.5 kHz (voice legibility + singer's-formant zone) | [S10][S13] |
| Air | shelf ~12 kHz | [S9] |
Balance is set by mic placement, not EQ -- in a single-mic take you cannot EQ voice and guitar
separately; any boost lifts both. [S8 forum quote in S9 search] Keep EQ moves small (<=3 dB). [I]

### 2.3 Violin
| Move | Value | Tag |
|---|---|---|
| HPF | ~150-180 Hz (violin's lowest note G3 = 196 Hz) | [I] |
| Keep | 270-600 Hz body; cut only if boomy from close mic | [S6][S15] |
| Nasal | -1 to -3 dB in 1-1.8 kHz if honky | [S7] |
| Brilliance | do not cut the 2-3 kHz bridge hill; if shrill, narrow cut ~2 kHz or ~5 kHz by ear | [S6][S15] |
| Harsh | gentle cut / low-pass > 6-8 kHz if scratchy | [S6][I] |

### 2.4 Saw duang **[I]** (derived from erhu + violin; verify by ear and FFT)
| Move | Value |
|---|---|
| HPF | ~200-250 Hz (below the low string; removes thumps/handling) |
| Membrane region | leave 1-3 kHz mostly flat; it is the instrument's character |
| Harshness | if piercing at close range, narrow -2 dB somewhere 2.5-4 kHz (sweep to find) |
| Scratch / bow noise | gentle cut or low-pass above ~6-8 kHz |
| Mic distance | farther (~0.5-1 m) is the first fix for buzz/scratch, before EQ |

### 2.5 Implications for the app's current EQ [I]
- Current presence peak is fixed at **4 kHz**. Good for speech; for singing a **3 kHz** center is closer to
  the singer's formant; for violin/saw duang a presence *boost* is usually unwanted (already bright).
  A per-preset center frequency or a "presence off" setting for instruments would be the minimal change.
- Current low-cut is one HPF -- fine. Per-source suggested defaults: speech 100 Hz, voice+guitar 75 Hz,
  violin 160 Hz, saw duang 220 Hz.

---

## 3. Dynamics

### 3.1 Compressor (app has none yet; only a peak limiter)
| Source | Ratio | Attack | Release | Gain reduction | Tag |
|---|---|---|---|---|---|
| Speech | 3:1-4:1 | 3-10 ms | 80-150 ms | 3-6 dB on loud words | [S11] |
| Singing | ~3:1, soft knee | medium (~10-30 ms) so consonants pass | 100-300 ms | 3-6 dB on loudest phrases | [S12] |
| Voice + acoustic guitar | 2:1-4:1 (lighter for a combined track) | 10-25 ms (keep pick transients) | 50-150 ms | 1-3 dB | [S9] |
| Violin / bowed | 2:1-3:1 | 30-50 ms (keeps bow articulation) | by ear, avoid pumping | a few dB | [S23] |
| Saw duang | as violin | 30-50 ms | by ear | <= 3 dB | [I] |

Bowed strings often need little or no compression; fast attack flattens bow-change transients. [S23]
For a single all-purpose default: **3:1, 10-20 ms attack, ~120 ms release, soft knee, threshold for ~3 dB GR**. [I]

### 3.2 Limiter
- Current: 1 ms lookahead, ~100 ms release, -1 dBFS ceiling. This is a standard safety limiter. [I]
- Release 100 ms is fine for speech; for sustained instruments (violin, saw duang) a longer release
  (~200-300 ms) pumps less if the limiter hits often. [I]
- The limiter should rarely act; if it acts constantly, input gain is too high. [I]

### 3.3 De-esser
- Detect 5-10 kHz band, compress only that band (split-band) or use a dynamic EQ. No standard
  threshold; set so only harsh "s" is reduced. [S12]
- A de-esser tuned to ~2-5 kHz can also tame guitar string squeak, but low-frequency reach and
  dulling are concerns. [S16]
- Do not de-ess violin/saw duang with a vocal setting -- their bright partials would be ducked. [I]

---

## 4. Noise reduction

### 4.1 How the app's reducer works
Spectral subtraction with a learned profile: gain `g = max(floor, 1 - 2*(mean + sens*dev)/mag)`,
fast attack / slow (0.7/0.3) release smoothing per bin.

### 4.2 Theory (Berouti-style spectral subtraction)
- **Musical noise**: random isolated spectral peaks left after subtraction that sound like short
  tones/"water". Caused by noise-estimate fluctuations and half-wave rectification. [S3][S24]
- **Over-subtraction (alpha)**: subtracting >1x the noise estimate suppresses wideband residual (the
  app uses 2x plus a deviation term). Too much -> isolated peaks -> more musical noise. [S24]
- **Spectral floor (beta)**: lower bound on gain; masks narrowband residual. A *higher* floor is often
  preferred because musical noise is more objectionable than steady hiss. [S24]
- There are no universal alpha/beta values; designers tune by ear. [S24]
- Music-specific study: methods that work on synthetic/speech signals are not necessarily acceptable
  for musical quality. [S3]

### 4.3 Recommendations for music [I]
- Music (sustained violin/saw duang notes, guitar decays, reverb tails) is more vulnerable than speech:
  low-level partials and decays fall near the noise profile and get gated, producing "warbling"
  and cut-off tails.
- For instrument presets: use a **shallower depth (floor ~ -6 to -10 dB instead of deeper)**, lower
  over-subtraction, and slower gain release.
- Keep reverb *after* noise reduction (current order is right) so the reducer never eats reverb tails.
- Larger FFT (better frequency resolution) suits sustained tonal music; smaller FFT suits speech
  transients. The app already has selectable FFT size.

### 4.4 Apple voice processing (`setVoiceProcessingEnabled` / VPIO)
- VPIO provides echo cancellation, noise suppression and AGC; it is built for voice chat. [S25]
- AGC can be toggled separately (`isVoiceProcessingAGCEnabled`). Playback may be forced to mono. [S25]
- Expect it to hurt music (sustained notes treated as noise, AGC pumping). Good for speech in a noisy
  room; for singing/instruments prefer it **off**. [I][U -- confirm by A/B recording]
- `.measurement` mode minimizes system DSP (no AGC / HPF) but gives low level; `.default` applies AGC
  and an HPF. No published frequency-response curves exist; measure with a sweep. [S26]

---

## 5. Reverb

### 5.1 Starting values [S/C]
| Parameter | Value | Tag |
|---|---|---|
| Decay (general vocal) | 0.8-1.8 s | [S27] |
| Decay (ballad) | longer; up to 4-5 s on a send | [S27] |
| Pre-delay | 40-80 ms lead vocal (range 50-150 ms quoted) -- keeps words clear | [S27] |
| Return low-cut | ~80 Hz or higher (tails pile up low end) | [S27] |
| Return high-cut | ~5 kHz (less obvious tail, less sibilance splash) | [S27] |
| Rule | tail should fall below the music before the next phrase | [S27] |

### 5.2 Per source [I]
- Speech: little or no reverb; short room (<0.8 s) at low mix.
- Singing + guitar: plate/hall 1.2-2 s, pre-delay ~40-60 ms, low mix.
- Violin / saw duang: hall 1.5-2.5 s suits sustained bowed tone; pre-delay 20-40 ms.

### 5.3 Implications for the app's Freeverb [I]
- Freeverb has no pre-delay and no return filters. Smallest improvements, in order of value:
  1. **Pre-delay** (a short delay line before the combs, ~20-60 ms).
  2. **Low-cut on the wet signal** (one HPF ~150-200 Hz) to stop mud.
  3. The existing `damp` already acts as a high-cut on the tail.
- Rough Freeverb decay: comb feedback 0.84 (room) ~ short, 0.938 (hall) ~ long; measure RT60 if exact
  values matter. [U]

---

## 6. Recording / placement notes (free quality, no DSP) [S/C]
- Capture the balance at recording time; fixing a single-mic blend later is much harder. [S9]
- Move the mic back (~30-45 cm for guitar) to reduce squeak, boom and pick noise. [S16]
- Small rooms: mud 200-400 Hz comes from the room; soft furnishings beat EQ. [I]

---

## 7. Suggested preset table (all [I], derived from sections 2-5)
| Preset | HPF | Presence | Comp | NR depth | Reverb |
|---|---|---|---|---|---|
| Speech | 100 Hz | +2 dB @ 4 kHz | 3:1, 5 ms / 100 ms | normal | off / room low |
| Sing + guitar | 75 Hz | +1.5 dB @ 3 kHz | 2.5:1, 15 ms / 120 ms | light | room/hall, low mix |
| Violin | 160 Hz | 0 | 2:1, 40 ms / 200 ms | light, slow release | hall |
| Saw duang | 220 Hz | 0 (or -2 dB @ ~3 kHz if piercing) | 2:1, 40 ms / 200 ms | light, slow release | hall |

Verify every preset by A/B recording on the real iPad (`windows/check_wav` can inspect output).

---

## Sources
1. [S1] Vocal EQ guides: https://www-cf.musehub.com/learn/how-to-eq-vocals , https://rysupaudio.com/blogs/news/how-to-eq-vocals , https://violetrecording.com/how-to-eq-vocals/
2. [S2] https://emastered.com/blog/female-vocal-eq , https://audient.com/ko/tutorial/how-to-eq-vocals/
3. [S3] Spectral techniques on musical audio (UFES): https://dspace5.ufes.br/handle/10/4076
4. [S6] Violin EQ / resonances: https://electricviolinshop.com/blogs/buying-guides/effects-for-violin-eq , https://www.violinist.com/discussion/archive/25862 , https://physerver.hamilton.edu/courses/Fall13/Phy175/ClassNotes/Class14_F13ViolinsHandouts.pdf
5. [S7] Schleske, tonal color and resonance profile: https://www.schleske.de/en/research/handbook-violinacoustics/tonal-color-and-the-resonance-profile.html , Curtin & Schleske (Strad 2004): https://www.schleske.de/fileadmin/user_upload/doc/Curtin_Schleske_Strad_Januar2004.pdf
6. [S8] https://www.musicguymixing.com/how-to-mix-acoustic-guitar-and-vocals/ , https://www.musicguymixing.com/?p=3561
7. [S9] https://www.masteringthemix.com/blogs/learn/everything-you-need-to-know-about-mixing-acoustic-guitars , https://www.acousticguitarforum.com/forums/showthread.php?p=7777705 , https://www.soundonsound.com/techniques/mix-rescue-stvitus-media
8. [S10] https://academy.producelikeapro.com/forums/topic/a-mixing-question/
9. [S11] Podcast/speech compression: https://violetrecording.com/how-to-mix-a-podcast/ , https://www.acast.com/blog/a-guide-to-vocal-compression-for-podcasters , https://www.thepodcasthost.com/equipment/how-to-use-compression/
10. [S12] Vocal compression / de-essing: https://www.sageaudio.com/articles/how-to-compress-vocals , https://violetrecording.com/how-to-compress-vocals/
11. [S13] Singer's formant: https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2023.1215370/epub , https://assta.org/proceedings/sst/sst2002/Papers/Millhouse070.pdf , https://www.speech.kth.se/qpsr/1995/1995_36_2-3_083-096.pdf
12. [S14] https://www.pevoc.org/pevoc07/Henrich-FP.htm , https://www.dpamicrophones.com/dict/singing-voices-and-frequencies/
13. [S15] Bridge hill: https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3871102/ , https://yadda.icm.edu.pl/baztech/element/bwmeta1.element.baztech-fa6c7e91-1960-4c16-9b65-40ac992d8a38 , https://engweb.swan.ac.uk/~adhikaris/BmUSD06/Presentations/JWoodhouse.pdf
14. [S16] Guitar squeak: https://recording.org/comment/acoustic-guitar-string-squeak-suppression , https://gearspace.com/threads/squeaks-strings.583165/ , https://discussions.apple.com/thread/1185457
15. [S17] https://en.wikipedia.org/wiki/Saw_duang
16. [S18] https://organology.net/instrument/saw-duang/ , https://wmic.net/thailand-saw-duang-aurelia/
17. [S19] Saw duang solo study (Thai): https://so05.tci-thaijo.org/index.php/RRBR/article/view/241470
18. [S20] Thai tuning: https://journal.iftawm.org/previous/vol4no2/garzoli/ , https://journal.isi.ac.id/index.php/IJCAS/article/view/1441
19. [S21] Erhu acoustics (1991, Acta Acustica sinica): https://jac.ac.cn/article/doi/10.15949/j.cnki.0371-0025.1991.01.011
20. [S22] https://wiki.ubc.ca/Course:PHYS341/Archive/2016wTerm2/Erhu_Acoustics
21. [S23] Bowed string compression: https://electricviolinshop.com/a/research-hq/post/effects-for-violin-compression , https://www.dummies.com/how-to/content/dynamic-music-compression-settings-for-stringed-in.html
22. [S24] Spectral subtraction parameters: https://signalprocessingsociety.org/sites/default/files/tutorial_sipa_2011_part1.pdf , https://www.vocal.com/noise-reduction/musical-noise/ , https://vocal.com/noise-reduction/spectral-subtraction/
23. [S25] Apple VPIO: https://developer.apple.com/library/ios/qa/qa1683/_index.html , https://www.mintlify.com/livekit/client-sdk-swift/api/audio/audio-session , https://developer.apple.com/forums/thread/28325
24. [S26] Measurement mode: https://developer.apple.com/forums/thread/695892 , https://forum.juce.com/t/disable-agc-and-highpass-filter-on-ios/12812 , https://developer.apple.com/forums/thread/25197
25. [S27] Reverb: https://www.waves.com/vocal-reverb-tips-to-make-your-mix-sing , https://rysupaudio.com/blogs/news/reverb-settings-for-vocals , https://forums.prosoundweb.com/index.php/topic,153060.10.html , https://newsletter.drewbrashler.com/p/reverb-pre-delay-low-cut

Gaps: no measured spectrum of saw duang found; no measured iPad built-in mic response per mode;
most mixing numbers come from blogs/forums. Next research step: record each instrument in the app,
FFT it, and add measured peaks to section 1.6 / 2.4.
