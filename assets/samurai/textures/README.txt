Letakkan tekstur samurai di folder ini (dari folder "textures" hasil download Sketchfab).
Nama file harus berformat <nama_material>_baseColor.png / _normal.png / _emissive.png, contoh:

  Cuerpo_low_mat_baseColor.png     Cuerpo_low_mat_normal.png
  Lompa_low_mat_baseColor.png      Lompa_low_mat_normal.png
  Sombrero_Mat_baseColor.png       Sombrero_Mat_normal.png
  Masc_mat_baseColor.png
  Ojo_Mat_baseColor.png            Ojo_Mat_emissive.png
  Cristalino_Mat_baseColor.png
  Frasco_Mat1_baseColor.png
  Zapas_Mat1_baseColor.png
  Medias_mat1_baseColor.png

player.gd memasangnya otomatis saat game berjalan. Material tanpa tekstur memakai warna placeholder
(FALLBACK_COLORS di scripts/player.gd).
