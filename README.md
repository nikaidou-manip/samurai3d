# Simple 3D RPG Prototype (Godot 4.3+)

Prototype action RPG third-person dengan karakter **samurai**, combat sederhana, dan musuh slime.
Dites dengan Godot 4.3 (import FBX/GLB bawaan, tanpa addon).

## Cara membuka
1. Buka **Godot 4.3 atau lebih baru** -> Import -> pilih `project.godot`.
2. Tunggu import selesai (pertama kali agak lama), lalu tekan **F5**.

## Kontrol
| Aksi | Tombol |
|---|---|
| Gerak (jogging) | W A S D |
| Sprint | Shift (tahan) |
| Lompat | Space |
| Dash (juga di udara) | Ctrl atau Q |
| Serang (combo 3 hit) | Klik kiri (tekan lagi saat animasi hampir selesai untuk lanjut combo) |
| Block | Klik kanan atau F (tahan) |
| Skill AoE | E |
| Kamera | Mouse |
| Lepas / tangkap mouse | Esc |

## Mekanik
- **Gerak relatif kamera**, karakter berputar halus ke arah gerak. Jalan memakai clip `run` diperlambat, sprint memakai kecepatan penuh.
- **Lompat** dengan fisika `CharacterBody3D` (ada balok untuk dipanjat).
- **Dash darat**: pose `dash_ground` ditahan, melesat ~4 m (0.35 dtk). **Dash udara**: saat melompat, tekan dash lagi
  (pose `dash_air`, 14 m/s, 0.4 dtk, melayang lurus), 1x per lompatan, reset saat mendarat. Kebal damage di 70% awal, cooldown 1.2 dtk.
- **Combo 3 serangan** (`attack1` -> `attack2` -> `attack3`): hit terjadi di momen ayunan, ada auto-aim ke musuh terdekat,
  input ter-buffer, bisa di-cancel ke dash atau lompat di akhir.
- **Block** (pose guard) menahan 85% damage dari depan.
- **Skill AoE (E)**: memakai clip `attack3` (tebasan melompat) diperlambat; aura emas menguat saat charge, lalu ledakan saat tebasan
  menghantam. Radius 6 m, damage 35, knockback kuat, cooldown 8 dtk, damage yang diterima saat casting dikurangi 50%.
  Efek: ring energi, cakram cahaya, partikel, kilat lampu (`scenes/shockwave.tscn`), layar bergetar.
- **Musuh slime** (`slime.glb`, 3 ekor): bounce idle bawaan, mengejar, menekuk dan memerah sebelum melompat menyerang,
  bisa di-stagger, respawn setelah 4 detik. Ukuran di-skala otomatis (`slime_width`).
- HUD: HP, cooldown dash, cooldown skill, hit counter. Player respawn jika HP habis.

## Catatan teknis tentang aset samurai
- Model (`assets/samurai/idle.fbx`) memakai rig Mixamo 65 tulang. Ukuran aslinya ~4.3 unit, jadi di-skala otomatis ke 1.8 m
  (`target_height`) berdasarkan tinggi tulang.
- `dash_ground.fbx`, `dash_air.fbx`, dan `block.fbx` hanya berisi 1-2 frame (pose, bukan animasi bergerak). Posenya ditahan,
  gerak dash dibuat lewat kode.
- Tidak ada clip power-up untuk samurai, jadi skill AoE memakai `attack3`. Untuk mengganti: tambahkan FBX-nya ke `ANIM_FILES`
  di `scripts/player.gd` dan ubah konstanta `SKILL_CLIP` serta `SKILL_HIT_FRAC` (momen ledakan, 0-1 dari durasi clip).
- Model samurai tidak punya mesh pedang, jadi serangan terlihat tanpa senjata.
- Hips pada clip lompat dibuang gerak vertikalnya (fisika yang melompat), root motion maju clip serangan diterapkan lewat kode.

## Tekstur
Tekstur samurai tidak tertanam di FBX. Letakkan di `assets/samurai/textures/` dengan nama `<material>_baseColor.png`
(juga `_normal.png`, `_emissive.png`); lihat `assets/samurai/textures/README.txt`. Dipasang otomatis oleh `player.gd`.
Selama belum ada, karakter memakai warna placeholder (kulit, celana indigo, topi jerami, dll.).

## Tuning cepat (Inspector node Player, atau konstanta `COMBO` di `scripts/player.gd`)
- Kaki "meluncur" saat lari -> sesuaikan `walk_speed`/`walk_anim_speed` dan `sprint_speed`/`sprint_anim_speed`.
- Timing damage serangan -> ubah `hit` (0-1 dari durasi clip) di `COMBO`; `cancel` = kapan boleh lanjut combo.
- Jarak dash -> `dash_speed`/`dash_time` (darat), `air_dash_speed`/`air_dash_time` (udara).
- Skill: grup **AoE Skill** (radius, damage, cooldown, kecepatan animasi).

## Struktur (semua bisa diedit di editor)
```
main.tscn             dunia: WorldEnvironment, Sun, Arena (Floor + Platform1-3), Player, Enemies (Dummy1-3), HUD
scenes/player.tscn    CharacterBody3D, Pivot/Model (samurai idle.fbx), CameraRig -> SpringArm3D -> Camera3D, ChargeAura, ChargeLight
scenes/dummy.tscn     musuh slime (Body/Slime = slime.glb, Label3D HP)
scenes/shockwave.tscn efek ledakan AoE (Wall, Disc, Particles, Flash)
scripts/              main.gd (input), player.gd, dummy.gd (slime), shockwave.gd, hud.gd
assets/samurai/       FBX samurai (model + animasi) dan folder textures/
assets/enemies/       slime.glb
```
Tombol input didaftarkan lewat kode di `main.gd`. UI HUD dibuat lewat kode di `hud.gd`.
