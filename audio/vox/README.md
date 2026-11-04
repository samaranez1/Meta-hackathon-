# Pre-recorded voice fallback clips

Spoken fallback for the voiceover clips backend (`scripts/voiceover.gd`).
Exact-line match by MD5: `vox_<md5(line)>.wav`. Dynamic AI lines fall
back to `../vox_cue.wav` (two-tone blip; the text is always on screen).
Rendered with `espeak -v en-us -s 170`; replace any file with a studio
recording under the same name to upgrade it. Key check:
`printf '%s' "<line>" | md5sum` must equal the vox_ name (Godot
`String.md5_text()` computes the same).

| file | line |
| ---- | ---- |
| vox_1c9f097e236dc773789992b49ad89903.wav | SECTOR 1 - NEON DRIFT. Wingman online. Guns are automatic - focus on dodging and grab every P pickup. |
| vox_fc1c27b8baca8da6e22389ddf0e38794.wav | SECTOR 2 - CRIMSON BELT. Wingman online. Snipers telegraph before firing. Strafe sideways, never sit still. |
| vox_c9bf1b9b2ae0668a90a3d96d6c02362e.wav | SECTOR 3 - CHROMA STORM. Wingman online. Elites drop the best loot. Save one bomb for the HYDRA's spiral. |
| vox_8f9264456165d432ce8ac51d4ef1a1b2.wav | SECTOR 4 - VOID EDGE. Wingman online. The REAPER cloaks before it dashes. Watch for the shimmer. |
| vox_f4d04aeebd84f782e1536fcdad526158.wav | SECTOR 5 - STAR EATER'S MAW. Wingman online. Final sector. Spend every bomb - there is nothing after this. |
| vox_e439038a86973c6e2f1ac6aedaec1219.wav | VEX WARDEN: 'Your little ship amuses me. It will make fine debris.' |
| vox_d61866bfbd63cd1a8f637caaa287cd7a.wav | NEBULA TWINS: 'Two minds. One crossfire. Zero survivors.' |
| vox_bd9568b1a72a73a3365594649f61693e.wav | CHROMA HYDRA: 'Cut one pattern down and two more take its place.' |
| vox_2e275a7376432e86dd654e5430f18c67.wav | VOID REAPER: 'I have already killed you. You are just catching up.' |
| vox_dcf3d26532640799f9de09f622398f0b.wav | STAR EATER PRIME: 'I unmade a thousand suns. You are a spark.' |
| vox_17606d08cb42e9164fe267a45500c7e3.wav | Wingman easing pressure - grab shields and breathe. |
| vox_9eb9da9cb3b3996400bce6e43aa4514b.wav | You are cruising - Wingman is turning up the heat. |
| vox_2c9110f673025def8c835f6a2eef6b20.wav | Holding steady. Keep moving in small circles. |
| vox_3562001ad685cb48686b4560dddc60b9.wav | Galaxy saved, pilot! Try a no-bomb run next - you clearly do not need the training wheels. |
| vox_25e8b35d337909515a2e80dbe87f2cde.wav | Good run to sector 1. Spend coins on HULL in the Hangar, and dodge toward the gaps, not away from bullets. |
| vox_43461aa85b5abc8eb7a0051ab17f56d7.wav | Good run to sector 2. Spend coins on HULL in the Hangar, and dodge toward the gaps, not away from bullets. |
| vox_d83d31be47fdd419664ea7e16a5cb485.wav | Good run to sector 3. Spend coins on HULL in the Hangar, and dodge toward the gaps, not away from bullets. |
| vox_aacdc0e11ec375369a04f03fa9715e4b.wav | Good run to sector 4. Spend coins on HULL in the Hangar, and dodge toward the gaps, not away from bullets. |
| vox_de8fe8fb2bb9c3eabca026028ba32c71.wav | Good run to sector 5. Spend coins on HULL in the Hangar, and dodge toward the gaps, not away from bullets. |
