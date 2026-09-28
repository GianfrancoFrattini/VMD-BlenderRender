##
## Blender Render (v5.2) - Renderizador Blender para VMD (ES)
## Perfiles Principled BSDF configurables desde VMD.
##

# No intenta reemplazar una version ya registrada al recargar el plugin en VMD.
if {[package provide render2k] eq ""} {
    package provide render2k 5.2
}

# Forzar la eliminacion del namespace anterior para que el menu se actualice
if {[namespace which ::Render2K::do_render] ne ""} {
    if {[namespace which ::Render2K::cancel_movie] ne "" &&
            [lsearch -exact [info args ::Render2K::cancel_movie] force] >= 0} {
        catch { ::Render2K::cancel_movie 1 }
    } else {
        catch { ::Render2K::cancel_movie }
    }
    catch { namespace delete ::Render2K }
}

namespace eval ::Render2K:: {
    namespace export render2k render2k_movie

    variable w ""
    # Se conserva para la API Tcl existente; Render2K solo usa Blender.
    variable engine "blender"
    variable filename "render2k"
    variable file_format "png"
    variable resolution_preset "2K (2560x1440)"
    variable custom_width 2560
    variable custom_height 1440
    variable resolution_info ""

    variable have_blender 0
    variable have_im 0
    variable have_ffmpeg 0
    variable gpu_name ""

    # Opciones Blender
    variable blender_render_engine "CYCLES"
    variable blender_samples 128
    variable blender_denoise 1
    variable blender_autorun 1
    variable blender_rotate 1

    # Iluminacion Blender
    # Tres luces tipo SUN forman un esquema de estudio estable, independiente
    # del tamano de la molecula. El multiplicador global permite aclarar u
    # oscurecer el render sin retocar las tres luces por separado.
    variable blender_light_multiplier 1.0
    variable blender_key_strength 4.0
    variable blender_fill_strength 2.0
    variable blender_rim_strength 2.5
    variable blender_sun_angle 20.0
    variable blender_ambient_strength 0.65
    variable blender_exposure 0.35

    # Fondo / World Blender
    variable blender_bg_strength 1.0
    variable bg_color "white"
    # flat: fondo visible + ambiente neutro; world: el color del fondo ilumina;
    # hdri: usa una imagen HDR/EXR para iluminar/reflejar.
    variable blender_background_mode "flat"
    variable blender_hdri_path ""
    variable blender_hdri_strength 1.0
    variable blender_hdri_rotation 0.0
    variable blender_hdri_visible 0

    # Pelicula Blender: cada frame de VMD se exporta a Wavefront y un unico
    # proceso Blender renderiza toda la secuencia antes de codificar el MP4.
    variable movie_molid "top"
    variable movie_start 0
    variable movie_end -1
    variable movie_stride 1
    variable movie_fps 30
    variable movie_crf 18
    variable movie_filename "render2k_movie"
    variable movie_resume 1
    variable movie_keep_assets 1
    variable movie_overwrite 0
    variable movie_lock_camera 1
    variable movie_running 0
    variable movie_run_id 0
    variable movie_cancel_requested 0
    variable movie_stage ""
    variable movie_after ""
    variable movie_cancel_after ""
    variable movie_pipe ""
    variable movie_process_kind ""
    variable movie_frame_specs [list]
    variable movie_jobs [list]
    variable movie_pending [list]
    variable movie_index 0
    variable movie_total 0
    variable movie_render_total 0
    variable movie_worker_complete 0
    variable movie_rendered_jobs [dict create]
    variable movie_active_molid -1
    variable movie_original_frame ""
    variable movie_camera [dict create]
    variable movie_settings [dict create]
    variable movie_scene [list]
    variable movie_source_crc_cache [dict create]
    variable movie_run_options [dict create]
    variable movie_output ""
    variable movie_temp_output ""
    variable movie_dir ""
    variable movie_worker ""
    variable movie_manifest ""
    variable movie_lock ""
    variable movie_signature ""
    variable movie_manifest_jobs [dict create]
    variable movie_width 0
    variable movie_height 0
    variable movie_status "Listo para renderizar una pelicula."
    variable movie_progress 0
    variable movie_progress_text "Sin trabajo activo"

    # =================================================================
    # PERFILES DE MATERIALES BLENDER (Principled BSDF)
    # {roughness metallic specular alpha transmission ior}
    # Alpha y Transmission son modos excluyentes: Alpha crea una capa
    # transparente legible; Transmission representa vidrio fisico.
    # El material VMD solo selecciona el perfil. Estos valores se aplican
    # al shader de Blender y determinan el aspecto del render final.
    # =================================================================
    variable blender_mat_map
    array set blender_mat_map {
        "Default"        {0.30 0.00 0.50 1.00 0.00 1.45}
        "Opaque"         {0.30 0.00 0.50 1.00 0.00 1.45}
        "Transparent"    {0.38 0.00 0.08 0.45 0.00 1.33}
        "BrushedMetal"   {0.35 1.00 0.70 1.00 0.00 1.45}
        "Diffuse"        {0.90 0.00 0.10 1.00 0.00 1.45}
        "Ghost"          {0.55 0.00 0.03 0.20 0.00 1.33}
        "Glass1"         {0.38 0.00 0.08 0.35 0.00 1.33}
        "Glass2"         {0.44 0.00 0.07 0.45 0.00 1.33}
        "Glass3"         {0.50 0.00 0.06 0.55 0.00 1.33}
        "Glossy"         {0.12 0.00 0.60 1.00 0.00 1.45}
        "HardPlastic"    {0.28 0.00 0.65 1.00 0.00 1.45}
        "MetallicPastel" {0.30 0.85 0.60 1.00 0.00 1.45}
        "Steel"          {0.25 1.00 0.80 1.00 0.00 1.45}
        "Translucent"    {0.50 0.00 0.08 0.55 0.00 1.33}
        "Edgy"           {0.45 0.00 0.35 1.00 0.00 1.45}
        "EdgyShiny"      {0.22 0.00 0.55 1.00 0.00 1.45}
        "EdgyGlass"      {0.42 0.00 0.10 0.50 0.00 1.33}
        "Goodsell"       {0.85 0.00 0.15 1.00 0.00 1.45}
        "AOShiny"        {0.28 0.00 0.55 1.00 0.00 1.45}
        "AOChalky"       {0.85 0.00 0.15 1.00 0.00 1.45}
        "AOEdgy"         {0.55 0.00 0.35 1.00 0.00 1.45}
        "BlownGlass"     {0.40 0.00 0.08 0.40 0.00 1.33}
        "GlassBubble"    {0.34 0.00 0.05 0.30 0.00 1.10}
        "RTChrome"       {0.03 1.00 0.90 1.00 0.00 1.45}
    }

    # Buffer de la pestaña de materiales. Se guarda al cambiar de perfil,
    # al pulsar Guardar y antes de renderizar desde la interfaz.
    variable blender_mat_selected "Opaque"
    variable blender_mat_active "Opaque"
    variable blender_mat_roughness 0.30
    variable blender_mat_metallic 0.00
    variable blender_mat_specular 0.50
    variable blender_mat_alpha 1.00
    variable blender_mat_transmission 0.00
    variable blender_mat_ior 1.45
    variable blender_mat_status ""

    array set resolutions {
        "HD (1280x720)"       {1280 720}
        "Full HD (1920x1080)" {1920 1080}
        "2K (2560x1440)"      {2560 1440}
        "4K (3840x2160)"      {3840 2160}
        "5K (5120x2880)"      {5120 2880}
        "8K (7680x4320)"      {7680 4320}
        "Custom"              {0 0}
    }
}

# ----------------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------------

proc ::Render2K::log {msg} {
    puts "blender-render: $msg"
}

proc ::Render2K::msg {icon title text} {
    log "$title -- $text"
    catch { tk_messageBox -type ok -icon $icon -message $text -title $title }
}

proc ::Render2K::find_exec {name} {
    if {![catch {exec which $name 2>@1} p]} { return [string trim $p] }
    return ""
}

proc ::Render2K::convert_to {src dst fmt} {
    variable have_im
    if {$have_im eq 0} { return 0 }
    set fmt [string toupper $fmt]
    if {$fmt eq "JPG"} { set fmt "JPEG" }
    if {$have_im eq "convert" || $have_im eq "magick"} {
        set cmd [list $have_im $src $dst]
    } else {
        set code {from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert("RGB")
kw = {"quality": 95} if sys.argv[3] == "JPEG" else {}
im.save(sys.argv[2], sys.argv[3], **kw)}
        set cmd [list python3 -c $code $src $dst $fmt]
    }
    if {[catch {exec {*}$cmd 2>@1} err]} {
        log "conversion fallo: $err"
        return 0
    }
    return 1
}

# ----------------------------------------------------------------------------
# Deteccion de Blender y hardware
# ----------------------------------------------------------------------------

proc ::Render2K::detect_all {} {
    variable have_blender
    variable have_im
    variable have_ffmpeg
    variable gpu_name

    set gpu_name ""
    if {![catch {exec nvidia-smi --query-gpu=name --format=csv,noheader 2>@1} out]} {
        set gpu_name [string trim [lindex [split $out "\n"] 0]]
    }

    set have_blender 0
    set b [find_exec blender]
    if {$b ne ""} { set have_blender $b }

    set have_im 0
    if {[find_exec convert] ne ""} {
        set have_im "convert"
    } elseif {[find_exec magick] ne ""} {
        set have_im "magick"
    } elseif {[find_exec python3] ne "" && ![catch {exec python3 -c "import PIL" 2>@1}]} {
        set have_im "python"
    }

    set have_ffmpeg [find_exec ffmpeg]

    log "Blender: $have_blender | GPU: [expr {$gpu_name ne "" ? $gpu_name : "no detectada"}] | conversion: $have_im | ffmpeg: [expr {$have_ffmpeg ne "" ? $have_ffmpeg : "no disponible"}]"
    return 1
}

proc ::Render2K::engine_available {e} {
    variable have_blender
    return [expr {$e eq "blender" && $have_blender ne 0}]
}

# ----------------------------------------------------------------------------
# Export OBJ + MTL para Blender
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# Mapeo materiales VMD (por representacion) -> Blender
# ----------------------------------------------------------------------------

# Perfiles disponibles, con Default siempre al principio.
proc ::Render2K::blender_material_keys {} {
    variable blender_mat_map
    set keys [list Default]
    foreach key [lsort [array names blender_mat_map]] {
        if {$key ne "Default"} { lappend keys $key }
    }
    return $keys
}

# Carga un perfil Blender en el buffer que usa la interfaz.
proc ::Render2K::load_blender_material {{key ""}} {
    variable blender_mat_map
    variable blender_mat_selected
    variable blender_mat_active
    variable blender_mat_roughness
    variable blender_mat_metallic
    variable blender_mat_specular
    variable blender_mat_alpha
    variable blender_mat_transmission
    variable blender_mat_ior
    variable blender_mat_status

    if {$key ne ""} { set blender_mat_selected $key }
    if {![info exists blender_mat_map($blender_mat_selected)]} {
        set blender_mat_selected "Default"
    }
    foreach {blender_mat_roughness blender_mat_metallic blender_mat_specular \
             blender_mat_alpha blender_mat_transmission blender_mat_ior} \
            $blender_mat_map($blender_mat_selected) { break }
    set blender_mat_active $blender_mat_selected
    set blender_mat_status "Perfil '$blender_mat_selected' cargado."
    return 1
}

# Valida y guarda el buffer de la interfaz en el perfil Blender activo.
proc ::Render2K::save_blender_material {{show_error 1}} {
    variable blender_mat_map
    variable blender_mat_selected
    variable blender_mat_active
    variable blender_mat_roughness
    variable blender_mat_metallic
    variable blender_mat_specular
    variable blender_mat_alpha
    variable blender_mat_transmission
    variable blender_mat_ior
    variable blender_mat_status

    if {$blender_mat_active eq "" || ![info exists blender_mat_map($blender_mat_active)]} {
        set blender_mat_active $blender_mat_selected
    }
    if {![info exists blender_mat_map($blender_mat_active)]} {
        set blender_mat_status "Perfil Blender no valido."
        if {$show_error} { msg error "Material Blender" $blender_mat_status }
        return 0
    }

    set values [list $blender_mat_roughness $blender_mat_metallic \
                     $blender_mat_specular $blender_mat_alpha \
                     $blender_mat_transmission $blender_mat_ior]
    set limits [list \
        [list "Rugosidad" 0.0 1.0] \
        [list "Metallic" 0.0 1.0] \
        [list "Nivel especular" 0.0 1.0] \
        [list "Alpha" 0.0 1.0] \
        [list "Transmision" 0.0 1.0] \
        [list "IOR" 1.0 3.0]]

    set normalized [list]
    foreach value $values limit $limits {
        foreach {label low high} $limit { break }
        if {![string is double -strict $value]} {
            set blender_mat_status "$label debe ser un numero entre $low y $high."
            if {$show_error} { msg error "Material Blender" $blender_mat_status }
            return 0
        }
        set number [expr {double($value)}]
        if {$number != $number || $number < $low || $number > $high} {
            set blender_mat_status "$label debe estar entre $low y $high."
            if {$show_error} { msg error "Material Blender" $blender_mat_status }
            return 0
        }
        lappend normalized [format "%.4f" $number]
    }

    if {[lindex $normalized 3] < 0.999 && [lindex $normalized 4] > 0.001} {
        set blender_mat_status "Alpha y Transmision son modos excluyentes. Usa Alpha para transparencia clara, o Alpha=1 con Transmision para vidrio fisico."
        if {$show_error} { msg error "Material Blender" $blender_mat_status }
        return 0
    }

    set blender_mat_map($blender_mat_active) $normalized
    set blender_mat_status "Perfil '$blender_mat_active' guardado para el proximo render Blender."
    return 1
}

# Guarda el perfil actual antes de cargar otro desde el menu de la interfaz.
proc ::Render2K::select_blender_material {key} {
    variable blender_mat_active
    if {$key eq $blender_mat_active} { return 1 }
    if {![save_blender_material]} { return 0 }
    return [load_blender_material $key]
}

# True solo si hay una interfaz abierta cuyos valores deben persistirse.
proc ::Render2K::blender_material_editor_open {} {
    variable w
    if {$w eq "" || [llength [info commands winfo]] == 0} { return 0 }
    if {[catch {winfo exists $w} exists]} { return 0 }
    return $exists
}

# Clave Blender para un material VMD ("" si no esta mapeado -> Default)
proc ::Render2K::mat_key {vmdmat {matmap {}}} {
    variable blender_mat_map
    set vmdmat [string trim $vmdmat]
    if {[dict size $matmap] > 0} {
        if {[dict exists $matmap $vmdmat]} { return $vmdmat }
        return "Default"
    }
    if {[info exists blender_mat_map($vmdmat)]} { return $vmdmat }
    return "Default"
}

proc ::Render2K::mat_params {key {matmap {}}} {
    variable blender_mat_map
    if {[dict size $matmap] > 0} {
        if {[dict exists $matmap $key]} { return [dict get $matmap $key] }
        return [dict get $matmap Default]
    }
    if {[info exists blender_mat_map($key)]} { return $blender_mat_map($key) }
    return $blender_mat_map(Default)
}

# Material VMD asignado a una representacion concreta
proc ::Render2K::rep_material {molid repidx} {
    if {[catch {molinfo $molid get "{material $repidx}"} m]} { return "" }
    set m [string trim $m]
    if {[llength $m] == 1} { return [string trim [lindex $m 0]] }
    return $m
}

# ColorID de VMD a partir de un nombre de color ("" si no existe).
# Compara el RGB del nombre con el RGB de cada ColorID numerico,
# porque 'colorinfo category ColorID' ya no existe en VMD 2.0.
proc ::Render2K::colorid_from_name {cname} {
    if {$cname eq ""} { return "" }
    if {[catch {set rgb [colorinfo rgb $cname]}]} { return "" }
    if {[llength $rgb] != 3} { return "" }
    set norm [lmap v $rgb {expr {round(double($v) * 10000.0)}}]
    for {set i 0} {$i < 256} {incr i} {
        if {[catch {set c [colorinfo rgb $i]}] || [llength $c] != 3} { continue }
        if {[lmap v $c {expr {round(double($v) * 10000.0)}}] eq $norm} { return $i }
    }
    return ""
}

# ColorID representativo de una representacion:
#   - si usa un color fijo -> su ColorID
#   - si usa coloring "Name" -> color del elemento del primer atomo
#   - otros metodos de color -> "" (VMD no escribe usemtl en el OBJ para
#     las reps de lineas; sin inyeccion heredan el material anterior)
proc ::Render2K::rep_color_index {molid repidx} {
    set val ""
    catch { set val [molinfo $molid get "{color $repidx}"] }
    set val [string trim $val]
    if {[llength $val] == 2 && [lindex $val 0] eq "ColorID" \
            && [string is integer -strict [lindex $val 1]]} {
        return [lindex $val 1]
    }
    set cid [colorid_from_name $val]
    if {$cid ne ""} { return $cid }
    if {$val ne "Name"} { return "" }
    set el ""
    catch {
        set seltext [molinfo $molid get "{selection $repidx}"]
        set sel [atomselect $molid $seltext]
        if {[$sel num] > 0} { set el [lindex [$sel get element] 0] }
        $sel delete
    }
    if {$el eq ""} { return "" }
    set cname ""
    foreach {e c} {H white O red N blue C gray S yellow P tan Z silver} {
        if {$e eq $el} { set cname $c; break }
    }
    if {$cname eq ""} { set cname "silver" }
    return [colorid_from_name $cname]
}

# Reescribe el OBJ exportado por VMD:
#   - detecta grupos "g vmd_mol<MOLID>_rep<REP>" y reescribe cada
#     "usemtl vmd_mat_cindex_N" a "usemtl vmd_<Clave>_cindex_N" segun el
#     material VMD de esa representacion.
#   - inyecta un usemtl inicial en cada representacion (con su color
#     representativo) porque VMD no emite usemtl para estilos de lineas.
#   - geometria fuera de representaciones (ejes, etc.) usa "Default".
# Devuelve una lista de pares {clave cindex} usados (para generar el MTL).
proc ::Render2K::rewrite_obj {objfile {matmap {}}} {
    set pairmap [dict create]
    set rep_profiles [dict create]
    set fallback_reps [list]
    set nrep 0
    set key "Default"
    set tmp "${objfile}.r2ktmp"

    set in [open $objfile r]
    set out [open $tmp w]
    while {[gets $in line] >= 0} {
        if {[regexp {^[[:space:]]*g[[:space:]]+vmd_mol([0-9]+)_rep([0-9]+)} \
                $line -> molid repidx]} {
            set vmdmat [rep_material $molid $repidx]
            set key [mat_key $vmdmat $matmap]
            dict set rep_profiles "$molid/$repidx" $key
            if {$key eq "Default" && $vmdmat ne "Default"} {
                lappend fallback_reps "$molid/$repidx='$vmdmat'"
            }
            incr nrep
            puts $out $line
            set cidx [rep_color_index $molid $repidx]
            if {$cidx ne ""} {
                puts $out "usemtl vmd_${key}_cindex_${cidx}"
                dict set pairmap "$key $cidx" 1
            }
            continue
        }
        if {[regexp {^[[:space:]]*usemtl[[:space:]]+vmd_mat_cindex_([0-9]+)[[:space:]]*$} \
                $line -> n]} {
            set line "usemtl vmd_${key}_cindex_${n}"
            dict set pairmap "$key $n" 1
        } elseif {[regexp {^[[:space:]]*g[[:space:]]+} $line]} {
            set key "Default"
        }
        puts $out $line
    }
    close $in
    close $out
    file rename -force $tmp $objfile

    set pairs [list]
    dict for {p _} $pairmap { lappend pairs $p }
    set profile_report [list]
    dict for {rep profile} $rep_profiles { lappend profile_report "$rep=$profile" }
    log "OBJ reescrito: $nrep representaciones mapeadas, [llength $pairs] materiales"
    if {[llength $profile_report]} {
        log "perfiles por representacion: [join $profile_report {, }]"
    }
    if {[llength $fallback_reps]} {
        log "ADVERTENCIA: perfiles VMD sin mapa Blender: [join $fallback_reps {, }]; se usa Default"
    }
    return $pairs
}

# Normaliza un RGB exportado por VMD para poder escribirlo en MTL/Python.
proc ::Render2K::normalize_rgb {rgb} {
    if {[llength $rgb] != 3} { return "" }
    set result [list]
    foreach component $rgb {
        if {[catch {set value [expr {double($component)}]}]} { return "" }
        lappend result [expr {max(0.0, min(1.0, $value))}]
    }
    return $result
}

# Conserva Kd del MTL que acaba de producir Wavefront. Ese valor incorpora
# exactamente la paleta y el rango Color Scale de la representacion DX.
proc ::Render2K::read_wavefront_colors {mtlfile} {
    set colors [dict create]
    if {![file exists $mtlfile] || [catch {set fp [open $mtlfile r]}]} {
        return $colors
    }

    set color_index ""
    while {[gets $fp line] >= 0} {
        if {[regexp {^[[:space:]]*newmtl[[:space:]]+} $line]} {
            set color_index ""
            if {[regexp {^[[:space:]]*newmtl[[:space:]]+vmd_.*_cindex_([0-9]+)[[:space:]]*$} \
                    $line -> index]} {
                set color_index $index
            }
            continue
        }
        if {$color_index ne "" && [regexp {^[[:space:]]*Kd[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)} \
                $line -> red green blue]} {
            set rgb [normalize_rgb [list $red $green $blue]]
            if {$rgb ne ""} { dict set colors $color_index $rgb }
        }
    }
    close $fp
    return $colors
}

# RGB de VMD para un ColorID o indice de Color Scale cuando el exportador no
# genero MTL. Los mapas Volume usan indices por encima de 255.
proc ::Render2K::color_scale_rgb {index} {
    if {![catch {set rgb [colorinfo rgb $index]}]} {
        set rgb [normalize_rgb $rgb]
        if {$rgb ne ""} { return $rgb }
    }
    return {0.600 0.600 0.600}
}

proc ::Render2K::material_rgb {index wavefront_colors} {
    if {[dict exists $wavefront_colors $index]} {
        return [dict get $wavefront_colors $index]
    }
    return [color_scale_rgb $index]
}

# Genera el MTL completo con el color exacto de cada ColorID o Color Scale
# de VMD y la opacidad derivada del material Blender mapeado.
proc ::Render2K::gen_mtl {mtlfile pairs wavefront_colors {matmap {}}} {
    set fp [open $mtlfile w]
    foreach pair $pairs {
        set key [lindex $pair 0]
        set n [lindex $pair 1]
        set rgb [material_rgb $n $wavefront_colors]
        foreach {rough metallic spec alpha transm ior} [mat_params $key $matmap] { break }
        puts $fp "newmtl vmd_${key}_cindex_$n"
        puts $fp [format "Ka %.3f %.3f %.3f" {*}[lmap v $rgb {expr {0.05 * $v}}]]
        puts $fp [format "Kd %.3f %.3f %.3f" {*}$rgb]
        puts $fp [format "Ks %.3f %.3f %.3f" $spec $spec $spec]
        puts $fp [format "Ns %.1f" [expr {max(8.0, (1.0 - $rough) * 1000.0)}]]
        puts $fp [format "d %.3f" $alpha]
        puts $fp "illum 2"
        puts $fp ""
    }
    close $fp
    return [llength $pairs]
}

proc ::Render2K::blender_bg_rgb {} {
    variable bg_color
    if {$bg_color eq "current"} {
        set bgname ""
        catch { set bgname [color Display Background] }
        if {$bgname ne "" && ![catch {set rgb [colorinfo rgb $bgname]}] && [llength $rgb] == 3} {
            return $rgb
        }
        return {0.020 0.020 0.030}
    }
    if {![catch {set rgb [colorinfo rgb $bg_color]}] && [llength $rgb] == 3} {
        return $rgb
    }
    return {0.020 0.020 0.030}
}

proc ::Render2K::vmd_vector {what fallback} {
    if {![catch {set v [display get $what]}] && [llength $v] == 3} {
        set out [list]
        foreach x $v {
            if {[catch {set xd [expr {double($x)}]}]} { return $fallback }
            lappend out [format "%.9g" $xd]
        }
        return $out
    }
    return $fallback
}

# Literal Python seguro para rutas de salida y de escena.
proc ::Render2K::py_quote {value} {
    set escaped [string map [list "\\" "\\\\" "'" "\\'" "\n" "\\n" "\r" "\\r"] $value]
    return "'$escaped'"
}

# La pelicula puede bloquear esta instantanea para que la camara no salte entre
# frames aunque la interfaz de VMD se actualice durante la exportacion.
proc ::Render2K::blender_camera_snapshot {} {
    set vmd_vsize 2.0
    catch {
        set tmp_vsize [display get height]
        if {[string is double -strict $tmp_vsize] && $tmp_vsize > 0} {
            set vmd_vsize $tmp_vsize
        }
    }
    return [dict create \
        eyepos [vmd_vector eyepos {0.0 0.0 10.0}] \
        eyedir [vmd_vector eyedir {0.0 0.0 -1.0}] \
        eyeup  [vmd_vector eyeup  {0.0 1.0 0.0}] \
        vsize $vmd_vsize]
}

# Congela todos los ajustes que se serializan en un script Blender. Esto evita
# que una pelicula mezcle perfiles o iluminacion si la interfaz cambia a mitad.
proc ::Render2K::blender_settings_snapshot {} {
    variable blender_render_engine
    variable blender_samples
    variable blender_denoise
    variable blender_rotate
    variable blender_light_multiplier
    variable blender_key_strength
    variable blender_fill_strength
    variable blender_rim_strength
    variable blender_sun_angle
    variable blender_ambient_strength
    variable blender_exposure
    variable blender_bg_strength
    variable blender_background_mode
    variable blender_hdri_path
    variable blender_hdri_strength
    variable blender_hdri_rotation
    variable blender_hdri_visible
    variable blender_mat_map
    set matmap [dict create]
    foreach key [lsort [array names blender_mat_map]] {
        dict set matmap $key $blender_mat_map($key)
    }
    return [dict create \
        render_engine $blender_render_engine \
        samples $blender_samples \
        denoise $blender_denoise \
        rotate $blender_rotate \
        light_multiplier $blender_light_multiplier \
        key_strength $blender_key_strength \
        fill_strength $blender_fill_strength \
        rim_strength $blender_rim_strength \
        sun_angle $blender_sun_angle \
        ambient_strength $blender_ambient_strength \
        exposure $blender_exposure \
        bg_strength $blender_bg_strength \
        background_mode $blender_background_mode \
        bg_rgb [blender_bg_rgb] \
        hdri_path $blender_hdri_path \
        hdri_strength $blender_hdri_strength \
        hdri_rotation $blender_hdri_rotation \
        hdri_visible $blender_hdri_visible \
        matmap $matmap]
}

# ----------------------------------------------------------------------------
# Generador de Script Blender Python (Lectura directa de MTL)
# ----------------------------------------------------------------------------

proc ::Render2K::gen_blender_py {pyscript objfile outfile width height pairs wavefront_colors {camera {}} {settings {}}} {
    variable blender_render_engine
    variable blender_samples
    variable blender_denoise
    variable blender_rotate
    variable blender_bg_strength
    variable blender_background_mode
    variable blender_mat_map

    if {[dict size $settings] == 0} {
        set settings [blender_settings_snapshot]
    }
    foreach {width height} [validate_resolution $width $height] { break }
    set rot "True"; if {![dict get $settings rotate]} { set rot "False" }
    set requested_engine "CYCLES"
    if {[string toupper [dict get $settings render_engine]] eq "EEVEE"} {
        set requested_engine "EEVEE"
    }

    set background_mode "FLAT"
    switch -- [string tolower [dict get $settings background_mode]] {
        world { set background_mode "WORLD" }
        hdri  { set background_mode "HDRI" }
    }

    set samples 128
    if {[string is integer -strict [dict get $settings samples]]} {
        set samples [expr {max(16, min(2048, [dict get $settings samples]))}]
    }

    # Limites deliberadamente amplios pero seguros para evitar renders negros
    # por errores de entrada y, a la vez, permitir escenas muy brillantes.
    set light_multiplier 1.0
    if {[string is double -strict [dict get $settings light_multiplier]]} {
        set light_multiplier [expr {max(0.0, min(5.0, double([dict get $settings light_multiplier])))}]
    }
    foreach {name fallback low high} {
        key_strength 4.0 0.0 20.0
        fill_strength 2.0 0.0 20.0
        rim_strength 2.5 0.0 20.0
        sun_angle 20.0 0.1 90.0
        ambient_strength 0.65 0.0 5.0
        exposure 0.35 -5.0 5.0
        bg_strength 1.0 0.0 10.0
        hdri_strength 1.0 0.0 10.0
        hdri_rotation 0.0 -360.0 360.0
    } {
        set value $fallback
        if {[dict exists $settings $name] && [string is double -strict [dict get $settings $name]]} {
            set value [expr {max($low, min($high, double([dict get $settings $name])))}]
        }
        set $name $value
    }

    set hdri_visible "False"
    if {[dict exists $settings hdri_visible] && [dict get $settings hdri_visible]} {
        set hdri_visible "True"
    }
    set hdri_path ""
    if {[dict exists $settings hdri_path]} { set hdri_path [string trim [dict get $settings hdri_path]] }
    if {$background_mode eq "HDRI"} {
        if {$hdri_path eq ""} {
            return -code error "Seleccionaste HDRI pero no indicaste un archivo .hdr/.exr."
        }
        if {![file exists $hdri_path]} {
            return -code error "No se encontro el HDRI: $hdri_path"
        }
        set hdri_path [file normalize $hdri_path]
    }

    set bg_rgb [dict get $settings bg_rgb]
    set bg_r [lindex $bg_rgb 0]
    set bg_g [lindex $bg_rgb 1]
    set bg_b [lindex $bg_rgb 2]
    set py [open $pyscript w]

    if {[dict size $camera] == 0} {
        set camera [blender_camera_snapshot]
    }
    set vmd_eyepos [dict get $camera eyepos]
    set vmd_eyedir [dict get $camera eyedir]
    set vmd_eyeup  [dict get $camera eyeup]
    set vmd_vsize  [dict get $camera vsize]
    set ep [join $vmd_eyepos {, }]
    set ed [join $vmd_eyedir {, }]
    set eu [join $vmd_eyeup {, }]

    puts $py "# Auto-generado por Render2K Blender (VMD) v5.2"
    puts $py "import bpy, math, mathutils, time"
    puts $py ""
    puts $py "OBJ  = [py_quote $objfile]"
    puts $py "OUT  = [py_quote $outfile]"
    puts $py "RESX = $width"
    puts $py "RESY = $height"
    puts $py "REQUESTED_ENGINE = '$requested_engine'"
    puts $py "BACKGROUND_MODE = '$background_mode'"
    puts $py "SAMPLES = $samples"
    puts $py "DENOISE = [expr {[dict get $settings denoise] ? {True} : {False}}]"
    puts $py "ROT_VMD = $rot"
    puts $py "VMD_EYEPOS = mathutils.Vector(($ep))"
    puts $py "VMD_EYEDIR = mathutils.Vector(($ed))"
    puts $py "VMD_EYEUP  = mathutils.Vector(($eu))"
    puts $py "VMD_SCREEN_HEIGHT = $vmd_vsize"
    puts $py "VMD_BG = ($bg_r, $bg_g, $bg_b)"
    puts $py "VMD_BG_STRENGTH = $bg_strength"
    puts $py "LIGHT_MULTIPLIER = $light_multiplier"
    puts $py "KEY_STRENGTH = $key_strength"
    puts $py "FILL_STRENGTH = $fill_strength"
    puts $py "RIM_STRENGTH = $rim_strength"
    puts $py "SUN_ANGLE = $sun_angle"
    puts $py "AMBIENT_STRENGTH = $ambient_strength"
    puts $py "EXPOSURE = $exposure"
    puts $py "HDRI_PATH = [py_quote $hdri_path]"
    puts $py "HDRI_STRENGTH = $hdri_strength"
    puts $py "HDRI_ROTATION = $hdri_rotation"
    puts $py "HDRI_VISIBLE = $hdri_visible"

    # Perfiles Principled BSDF configurados en la interfaz de Render2K.
    puts $py "MATMAP = {}"
    array set material_map [dict get $settings matmap]
    foreach {vmdmat params} [array get material_map] {
        foreach {rough metallic spec alpha transm ior} $params { break }
        puts $py [format {MATMAP[r"%s"] = (%.6f, %.6f, %.6f, %.6f, %.6f, %.6f)} \
            $vmdmat $rough $metallic $spec $alpha $transm $ior]
    }
    # Asociacion exacta de cada material MTL generado con su perfil Blender.
    # No se infiere desde el nombre para evitar que un fallo termine en Default.
    puts $py "MATERIAL_PROFILES = {}"
    foreach pair $pairs {
        set key [lindex $pair 0]
        set n [lindex $pair 1]
        puts $py [format {MATERIAL_PROFILES[r"vmd_%s_cindex_%s"] = r"%s"} \
            $key $n $key]
    }
    # El importador OBJ de Blender no siempre transfiere Kd al Principled.
    # Se serializa el RGB que VMD exporto para preservar cada Color Scale.
    puts $py "MATERIAL_COLORS = {}"
    foreach pair $pairs {
        set key [lindex $pair 0]
        set n [lindex $pair 1]
        foreach {red green blue} [material_rgb $n $wavefront_colors] { break }
        puts $py [format {MATERIAL_COLORS[r"vmd_%s_cindex_%s"] = (%.6f, %.6f, %.6f)} \
            $key $n $red $green $blue]
    }
    puts $py ""
    puts $py {bpy.ops.wm.read_factory_settings(use_empty=True)}
    puts $py {try:}
    puts $py {    if hasattr(bpy.ops.wm, 'obj_import'):}
    puts $py {        bpy.ops.wm.obj_import(filepath=OBJ)}
    puts $py {    else:}
    puts $py {        bpy.ops.import_scene.obj(filepath=OBJ)}
    puts $py {except Exception as exc:}
    puts $py {    raise RuntimeError("No se pudo importar OBJ %s: %s" % (OBJ, exc)) from exc}
    puts $py {meshes = [o for o in bpy.data.objects if o.type == 'MESH']}
    puts $py {if not meshes: raise RuntimeError("OBJ sin geometria")}
    puts $py "if ROT_VMD:"
    puts $py "    for o in meshes:"
    puts $py "        o.rotation_euler = (math.radians(90), 0, 0)"
    puts $py "    bpy.context.view_layer.update()"
    puts $py ""

    # =================================================================
    # PERFILES BLENDER -> PRINCIPLED BSDF (asignados por representacion)
    # Nombres generados por Render2K: vmd_<Clave>_cindex_<N>
    # =================================================================
    puts $py "import re"
    puts $py "def _set_input(bsdf, names, value):"
    puts $py "    for name in names:"
    puts $py "        sock = bsdf.inputs.get(name)"
    puts $py "        if sock is not None:"
    puts $py "            sock.default_value = value"
    puts $py "            return True"
    puts $py "    return False"
    puts $py ""
    puts $py "def _link_surface(nt, output, shader):"
    puts $py {    for link in list(output.inputs['Surface'].links):}
    puts $py {        nt.links.remove(link)}
    puts $py {    nt.links.new(shader, output.inputs['Surface'])}
    puts $py ""
    puts $py {def _canonical_material_name(name):}
    puts $py {    return re.sub(r'\.[0-9]+$', '', name)}
    puts $py ""
    puts $py {print("R2K: Aplicando perfiles Principled BSDF de Blender...")}
    puts $py {unmapped_materials = []}
    puts $py {applied_profiles = {}}
    puts $py {for mat in bpy.data.materials:}
    puts $py {    material_name = _canonical_material_name(mat.name)}
    puts $py {    key = MATERIAL_PROFILES.get(material_name)}
    puts $py {    base_rgb = MATERIAL_COLORS.get(material_name)}
    puts $py {    if key is None or base_rgb is None:}
    puts $py {        unmapped_materials.append(mat.name)}
    puts $py {        continue}
    puts $py {    if key not in MATMAP:}
    puts $py {        raise RuntimeError("Perfil Blender no definido para %s: %s" % (mat.name, key))}
    puts $py {    rough, metallic, spec, alpha, transm, ior = MATMAP[key]}
    puts $py {    nt = mat.node_tree}
    puts $py {    if nt is None:}
    puts $py {        mat.use_nodes = True}
    puts $py {        nt = mat.node_tree}
    puts $py {    bsdf = next((node for node in nt.nodes if node.type == 'BSDF_PRINCIPLED'), None)}
    puts $py {    if bsdf is None: bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')}
    puts $py {    out = next((node for node in nt.nodes if node.type == 'OUTPUT_MATERIAL'), None)}
    puts $py {    if out is None: out = nt.nodes.new('ShaderNodeOutputMaterial')}
    puts $py {}
    puts $py {    if alpha < 0.999 and transm > 0.001:}
    puts $py {        raise RuntimeError("Alpha y Transmission no se pueden combinar: %s" % mat.name)}
    puts $py {    # No dependemos del Kd que Blender importe: conserva Color Scale.}
    puts $py {    base_color = (base_rgb[0], base_rgb[1], base_rgb[2], 1.0)}
    puts $py {    _set_input(bsdf, ['Base Color'], base_color)}
    puts $py {    _set_input(bsdf, ['Roughness'], rough)}
    puts $py {    _set_input(bsdf, ['Metallic'], metallic)}
    puts $py {    _set_input(bsdf, ['IOR'], ior)}
    puts $py {    _set_input(bsdf, ['Specular IOR Level', 'Specular'], spec)}
    puts $py {    _set_input(bsdf, ['Transmission Weight', 'Transmission'], transm)}
    puts $py {    _set_input(bsdf, ['Alpha'], 1.0)}
    puts $py {}
    puts $py {    if alpha < 0.999:}
    puts $py {        transparent = nt.nodes.get('R2K Transparent')}
    puts $py {        if transparent is None: transparent = nt.nodes.new('ShaderNodeBsdfTransparent')}
    puts $py {        transparent.name = 'R2K Transparent'}
    puts $py {        _set_input(transparent, ['Color'], (1.0, 1.0, 1.0, 1.0))}
    puts $py {        mix = nt.nodes.get('R2K Alpha Mix')}
    puts $py {        if mix is None: mix = nt.nodes.new('ShaderNodeMixShader')}
    puts $py {        mix.name = 'R2K Alpha Mix'}
    puts $py {        mix.inputs[0].default_value = alpha}
    puts $py {        for socket in (mix.inputs[1], mix.inputs[2]):}
    puts $py {            for link in list(socket.links): nt.links.remove(link)}
    puts $py {        nt.links.new(transparent.outputs['BSDF'], mix.inputs[1])}
    puts $py {        nt.links.new(bsdf.outputs['BSDF'], mix.inputs[2])}
    puts $py {        _link_surface(nt, out, mix.outputs['Shader'])}
    puts $py {        try: mat.surface_render_method = 'BLENDED'}
    puts $py {        except:}
    puts $py {            try: mat.blend_method = 'BLEND'}
    puts $py {            except: pass}
    puts $py {        try: mat.diffuse_color = (base_color[0], base_color[1], base_color[2], alpha)}
    puts $py {        except: pass}
    puts $py {        mat['r2k_transparency_mode'] = 'alpha'}
    puts $py {    else:}
    puts $py {        _link_surface(nt, out, bsdf.outputs['BSDF'])}
    puts $py {        try: mat.diffuse_color = (base_color[0], base_color[1], base_color[2], 1.0)}
    puts $py {        except: pass}
    puts $py {        mat['r2k_transparency_mode'] = 'glass' if transm > 0.001 else 'opaque'}
    puts $py {    mat["r2k_profile"] = key}
    puts $py {    mat["r2k_base_color"] = base_rgb}
    puts $py {    applied_profiles[key] = applied_profiles.get(key, 0) + 1}
    puts $py {}
    puts $py {if unmapped_materials:}
    puts $py {    raise RuntimeError("Materiales OBJ sin perfil Blender: " + ", ".join(sorted(unmapped_materials)))}
    puts $py {bpy.context.view_layer.update()}
    puts $py {for key in sorted(applied_profiles):}
    puts $py {    rough, metallic, spec, alpha, transm, ior = MATMAP[key]}
    puts $py {    print("R2K_PROFILE: %s (%d material(es), roughness=%.3f, metallic=%.3f, specular=%.3f, alpha=%.3f, transmission=%.3f, ior=%.3f)" % (key, applied_profiles[key], rough, metallic, spec, alpha, transm, ior))}
    puts $py {print("R2K_MATERIALS: %d materiales mapeados automaticamente" % len(bpy.data.materials))}

    # =================================================================
    # CAMARA ORTOGRAFICA
    # =================================================================
    puts $py "if ROT_VMD:"
    puts $py "    C3 = mathutils.Matrix.Rotation(math.radians(90.0), 3, 'X')"
    puts $py "else:"
    puts $py "    C3 = mathutils.Matrix.Identity(3)"
    puts $py {cam_pos = C3 @ VMD_EYEPOS}
    puts $py {look_dir = (C3 @ VMD_EYEDIR).normalized()}
    puts $py {up_dir = (C3 @ VMD_EYEUP).normalized()}
    puts $py {up_dir = (up_dir - look_dir * up_dir.dot(look_dir)).normalized()}
    puts $py {right_dir = look_dir.cross(up_dir).normalized()}
    puts $py {up_dir = right_dir.cross(look_dir).normalized()}
    puts $py "R = mathutils.Matrix(((right_dir.x, up_dir.x, -look_dir.x),"
    puts $py "                       (right_dir.y, up_dir.y, -look_dir.y),"
    puts $py "                       (right_dir.z, up_dir.z, -look_dir.z)))"
    puts $py {cam = bpy.data.cameras.new("R2KCam")}
    puts $py {cam.type = 'ORTHO'}
    puts $py {cam.ortho_scale = max(1.0e-6, VMD_SCREEN_HEIGHT)}
    puts $py {camo = bpy.data.objects.new("R2KCam", cam)}
    puts $py {bpy.context.scene.collection.objects.link(camo)}
    puts $py {camo.location = cam_pos}
    puts $py {camo.rotation_euler = R.to_4x4().to_euler('XYZ')}
    puts $py {bpy.context.scene.camera = camo}
    puts $py {cam.clip_start = 0.001}
    puts $py {cam.clip_end = 100000.0}
    puts $py ""

    # Iluminacion de estudio. SUN hace que el resultado no dependa del tamano
    # absoluto del modelo molecular. Se exponen intensidades y suavidad en VMD.
    puts $py "def mk_sun(name, energy, rot, loc=(0,0,0)):"
    puts $py "    li = bpy.data.lights.new(name, 'SUN')"
    puts $py "    li.energy = max(0.0, energy * LIGHT_MULTIPLIER)"
    puts $py "    li.angle = math.radians(SUN_ANGLE)"
    puts $py "    ob = bpy.data.objects.new(name, li)"
    puts $py "    ob.rotation_euler = rot"
    puts $py "    ob.location = loc"
    puts $py "    bpy.context.scene.collection.objects.link(ob)"
    puts $py "    return ob"
    puts $py {mk_sun("R2K Key",  KEY_STRENGTH,  (math.radians(45),  math.radians(15),  math.radians(30)))}
    puts $py {mk_sun("R2K Fill", FILL_STRENGTH, (math.radians(30),  math.radians(-40), math.radians(-120)))}
    puts $py {mk_sun("R2K Rim",  RIM_STRENGTH,  (math.radians(-35), math.radians(20),  math.radians(170)))}
    puts $py {print("R2K_LIGHTS: key=%.3f fill=%.3f rim=%.3f multiplier=%.3f ambient=%.3f exposure=%.3f" % (KEY_STRENGTH, FILL_STRENGTH, RIM_STRENGTH, LIGHT_MULTIPLIER, AMBIENT_STRENGTH, EXPOSURE))}

    # Fondo visible e iluminacion del World.
    # FLAT: la camara ve el color elegido (blanco por defecto), mientras que
    #       materiales/reflejos reciben un ambiente blanco regulable. Evita el
    #       problema anterior donde el World era negro y la escena quedaba oscura.
    # WORLD: el color del World ilumina y tambien es visible.
    # HDRI: la textura ilumina/refleja; por defecto la camara sigue viendo el
    #       fondo elegido, aunque se puede activar "Ver HDRI".
    puts $py {sc = bpy.context.scene}
    puts $py {world = bpy.data.worlds.new("R2KWorld")}
    puts $py {world.use_nodes = True}
    puts $py {sc.world = world}
    puts $py {world_nt = world.node_tree}
    puts $py {if world_nt is None: raise RuntimeError("No se pudo crear el World node tree")}
    puts $py {world_nt.nodes.clear()}
    puts $py {world_out = world_nt.nodes.new('ShaderNodeOutputWorld')}
    puts $py {visible_bg = world_nt.nodes.new('ShaderNodeBackground')}
    puts $py {visible_bg.name = 'R2K Camera Background'}
    puts $py {visible_bg.inputs['Color'].default_value = (*VMD_BG, 1.0)}
    puts $py {visible_bg.inputs['Strength'].default_value = 1.0}
    puts $py {if BACKGROUND_MODE == 'FLAT':}
    puts $py {    ambient_bg = world_nt.nodes.new('ShaderNodeBackground')}
    puts $py {    ambient_bg.name = 'R2K Ambient'}
    puts $py {    ambient_bg.inputs['Color'].default_value = (1.0, 1.0, 1.0, 1.0)}
    puts $py {    ambient_bg.inputs['Strength'].default_value = AMBIENT_STRENGTH}
    puts $py {    light_path = world_nt.nodes.new('ShaderNodeLightPath')}
    puts $py {    mix_bg = world_nt.nodes.new('ShaderNodeMixShader')}
    puts $py {    world_nt.links.new(light_path.outputs['Is Camera Ray'], mix_bg.inputs[0])}
    puts $py {    world_nt.links.new(ambient_bg.outputs[0], mix_bg.inputs[1])}
    puts $py {    world_nt.links.new(visible_bg.outputs[0], mix_bg.inputs[2])}
    puts $py {    world_nt.links.new(mix_bg.outputs[0], world_out.inputs['Surface'])}
    puts $py {elif BACKGROUND_MODE == 'WORLD':}
    puts $py {    world_bg = world_nt.nodes.new('ShaderNodeBackground')}
    puts $py {    world_bg.name = 'R2K World Color'}
    puts $py {    world_bg.inputs['Color'].default_value = (*VMD_BG, 1.0)}
    puts $py {    world_bg.inputs['Strength'].default_value = VMD_BG_STRENGTH}
    puts $py {    world_nt.links.new(world_bg.outputs[0], world_out.inputs['Surface'])}
    puts $py {elif BACKGROUND_MODE == 'HDRI':}
    puts $py {    env_tex = world_nt.nodes.new('ShaderNodeTexEnvironment')}
    puts $py {    env_tex.name = 'R2K HDRI'}
    puts $py {    try:}
    puts $py {        env_tex.image = bpy.data.images.load(HDRI_PATH, check_existing=True)}
    puts $py {    except Exception as exc:}
    puts $py {        raise RuntimeError("No se pudo cargar HDRI %s: %s" % (HDRI_PATH, exc)) from exc}
    puts $py {    texcoord = world_nt.nodes.new('ShaderNodeTexCoord')}
    puts $py {    mapping = world_nt.nodes.new('ShaderNodeMapping')}
    puts $py {    mapping.inputs['Rotation'].default_value[2] = math.radians(HDRI_ROTATION)}
    puts $py {    hdri_bg = world_nt.nodes.new('ShaderNodeBackground')}
    puts $py {    hdri_bg.name = 'R2K HDRI Lighting'}
    puts $py {    hdri_bg.inputs['Strength'].default_value = HDRI_STRENGTH}
    puts $py {    world_nt.links.new(texcoord.outputs['Generated'], mapping.inputs['Vector'])}
    puts $py {    world_nt.links.new(mapping.outputs['Vector'], env_tex.inputs['Vector'])}
    puts $py {    world_nt.links.new(env_tex.outputs['Color'], hdri_bg.inputs['Color'])}
    puts $py {    if HDRI_VISIBLE:}
    puts $py {        world_nt.links.new(hdri_bg.outputs[0], world_out.inputs['Surface'])}
    puts $py {    else:}
    puts $py {        light_path = world_nt.nodes.new('ShaderNodeLightPath')}
    puts $py {        mix_bg = world_nt.nodes.new('ShaderNodeMixShader')}
    puts $py {        world_nt.links.new(light_path.outputs['Is Camera Ray'], mix_bg.inputs[0])}
    puts $py {        world_nt.links.new(hdri_bg.outputs[0], mix_bg.inputs[1])}
    puts $py {        world_nt.links.new(visible_bg.outputs[0], mix_bg.inputs[2])}
    puts $py {        world_nt.links.new(mix_bg.outputs[0], world_out.inputs['Surface'])}
    puts $py {else:}
    puts $py {    raise RuntimeError("Modo de fondo desconocido: %s" % BACKGROUND_MODE)}
    puts $py {print("R2K_WORLD: mode=%s world=%.3f hdri=%.3f hdri_visible=%s" % (BACKGROUND_MODE, VMD_BG_STRENGTH, HDRI_STRENGTH, HDRI_VISIBLE))}

    # Motor Blender y sus opciones especificas
    puts $py {def _select_engine(scene, requested):}
    puts $py {    candidates = {'CYCLES': ('CYCLES',), 'EEVEE': ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT')}.get(requested)}
    puts $py {    if not candidates: raise RuntimeError("Motor solicitado invalido: %r" % requested)}
    puts $py {    errors = []}
    puts $py {    for ident in candidates:}
    puts $py {        try:}
    puts $py {            scene.render.engine = ident}
    puts $py {        except Exception as exc:}
    puts $py {            errors.append("%s: %s" % (ident, exc))}
    puts $py {            continue}
    puts $py {        if scene.render.engine == ident: return ident}
    puts $py {    raise RuntimeError("Motor %s no disponible (%s)" % (requested, "; ".join(errors)))}
    puts $py {}
    puts $py {def _set_int_rna(owner, name, value):}
    puts $py {    prop = owner.bl_rna.properties.get(name)}
    puts $py {    if prop is None: return False}
    puts $py {    try:}
    puts $py {        value = max(int(prop.hard_min), min(int(value), int(prop.hard_max)))}
    puts $py {        setattr(owner, name, value)}
    puts $py {    except (TypeError, ValueError, OverflowError):}
    puts $py {        return False}
    puts $py {    return True}
    puts $py {}
    puts $py {engine_id = _select_engine(sc, REQUESTED_ENGINE)}
    puts $py {try: sc.render.film_transparent = False}
    puts $py {except Exception: pass}
    puts $py {if engine_id == 'CYCLES':}
    puts $py {    cycles = getattr(sc, 'cycles', None)}
    puts $py {    if cycles is None: raise RuntimeError("Cycles no esta disponible")}
    puts $py {    dev = 'CPU'}
    puts $py {    try:}
    puts $py {        addon = bpy.context.preferences.addons.get('cycles')}
    puts $py {        if addon is not None:}
    puts $py {            prefs = addon.preferences}
    puts $py {            for ctype in ('OPTIX', 'CUDA'):}
    puts $py {                prefs.compute_device_type = ctype}
    puts $py {                prefs.get_devices()}
    puts $py {                found = False}
    puts $py {                for dv in prefs.devices:}
    puts $py {                    dv.use = (dv.type == ctype)}
    puts $py {                    if dv.use: found = True}
    puts $py {                if found:}
    puts $py {                    dev = ctype}
    puts $py {                    break}
    puts $py {    except Exception:}
    puts $py {        pass}
    puts $py {    cycles.device = 'GPU' if dev != 'CPU' else 'CPU'}
    puts $py {    if not _set_int_rna(cycles, 'samples', SAMPLES): raise RuntimeError("No se pudieron configurar samples de Cycles")}
    puts $py {    if hasattr(cycles, 'use_denoising'): cycles.use_denoising = DENOISE}
    puts $py {    for prop, value in (('caustics_reflective', False), ('caustics_refractive', False), ('transparent_max_bounces', 16), ('transmission_bounces', 12)):}
    puts $py {        try: setattr(cycles, prop, value)}
    puts $py {        except Exception: pass}
    puts $py {else:}
    puts $py {    eevee = getattr(sc, 'eevee', None) or getattr(sc, 'eevee_next', None)}
    puts $py {    if eevee is None: raise RuntimeError("No hay ajustes Eevee disponibles")}
    puts $py {    if not (_set_int_rna(eevee, 'taa_render_samples', SAMPLES) or _set_int_rna(eevee, 'taa_samples', SAMPLES)):}
    puts $py {        raise RuntimeError("No se pudieron configurar samples de Eevee")}
    puts $py {print("R2K_ENGINE: %s" % engine_id)}
    puts $py {sc.render.resolution_x = RESX}
    puts $py {sc.render.resolution_y = RESY}
    puts $py {sc.render.resolution_percentage = 100}
    puts $py {# Standard conserva un fondo blanco puro. Si el HDRI es visible, AgX}
    puts $py {# suele dar un resultado fotografico mas agradable y mayor rango dinamico.}
    puts $py {transforms = ('AgX', 'Filmic', 'Standard') if (BACKGROUND_MODE == 'HDRI' and HDRI_VISIBLE) else ('Standard',)}
    puts $py {for transform in transforms:}
    puts $py {    try:}
    puts $py {        sc.view_settings.view_transform = transform}
    puts $py {        break}
    puts $py {    except Exception:}
    puts $py {        pass}
    puts $py {if BACKGROUND_MODE != 'HDRI' or not HDRI_VISIBLE:}
    puts $py {    if sc.view_settings.view_transform != 'Standard':}
    puts $py {        raise RuntimeError("El fondo blanco/plano requiere el transform Standard")}
    puts $py {sc.view_settings.exposure = EXPOSURE}
    puts $py {sc.view_settings.gamma = 1.0}
    puts $py {sc.render.image_settings.file_format = 'PNG'}
    puts $py {sc.render.filepath = OUT}
    puts $py ""
    puts $py {t0 = time.time()}
    puts $py {bpy.ops.render.render(write_still=True)}
    puts $py {print("R2K_BLENDER_TIME: %.1fs" % (time.time()-t0))}
    puts $py {print("R2K_BLENDER_DONE")}
    close $py
    return 1
}

proc ::Render2K::run_blender {pyscript} {
    variable have_blender
    if {$have_blender eq 0} {
        log "Blender no esta disponible."
        return ""
    }

    set outbuf ""
    set cmd [list $have_blender -b -P $pyscript 2>@1]
    if {[catch {set fp [open "|$cmd" r]} err]} {
        log "no se pudo iniciar Blender: $err"
        return ""
    }
    while {[gets $fp line] >= 0} {
        puts "blender: $line"
        if {[string match "R2K_*" $line]} { append outbuf "$line\n" }
    }
    if {[catch {close $fp} err]} {
        if {$err ni {CHILDSTATUS 0 0}} { log "blender termino con: $err" }
    }
    return $outbuf
}

# ----------------------------------------------------------------------------
# Exportacion y render Blender
# ----------------------------------------------------------------------------

proc ::Render2K::export_blender_frame {filename width height {camera {}} {settings {}}} {
    foreach {width height} [validate_resolution $width $height] { break }
    set obj [file normalize "${filename}.obj"]
    set mtl [file normalize "${filename}.mtl"]
    set py  [file normalize "${filename}_blender.py"]
    set png [file normalize "${filename}.png"]
    file mkdir [file dirname $obj]
    if {[dict size $settings] == 0} { set settings [blender_settings_snapshot] }
    set matmap [dict create]
    catch { set matmap [dict get $settings matmap] }

    set oldaxes "off"
    catch { set oldaxes [axes location] }
    catch { axes location off }
    log "exportando escena Wavefront OBJ (puede tardar en escenas grandes)..."
    set rc [catch {render Wavefront $obj} err options]
    catch { axes location $oldaxes }
    if {$rc} { return -options $options $err }
    if {![file exists $obj]} {
        return -code error "VMD no genero el archivo $obj"
    }

    # Capturar Kd antes de regenerar el MTL conserva la paleta Color Scale
    # exacta de QuickSurf y de cualquier otra representacion coloreada.
    set wavefront_colors [read_wavefront_colors $mtl]
    if {[dict size $wavefront_colors]} {
        log "Colores Wavefront: [dict size $wavefront_colors] RGB conservados desde MTL"
    } else {
        log "ADVERTENCIA: MTL sin colores Kd; se usara colorinfo como respaldo"
    }

    # VMD solo aporta la asignacion de perfil y el color; el aspecto PBR
    # se define con los perfiles Blender y se aplica en el script Python.
    set pairs [rewrite_obj $obj $matmap]
    set nmat [gen_mtl $mtl $pairs $wavefront_colors $matmap]
    log "Materiales Blender: $nmat materiales generados desde perfiles Principled BSDF"
    gen_blender_py $py $obj $png $width $height $pairs $wavefront_colors $camera $settings

    return [dict create obj $obj mtl $mtl py $py png $png materials $nmat]
}

proc ::Render2K::render_engine_blender {filename width height} {
    variable blender_render_engine
    variable blender_autorun
    variable file_format

    if {[blender_material_editor_open] && ![save_blender_material]} {
        return ""
    }

    if {[catch {set exported [export_blender_frame $filename $width $height]} err]} {
        msg error "Error exportando OBJ" $err
        return ""
    }
    set obj [dict get $exported obj]
    set mtl [dict get $exported mtl]
    set py  [dict get $exported py]
    set png [dict get $exported png]

    if {!$blender_autorun} {
        log "OBJ+MTL+script listos (modo 'solo exportar'):"
        log "  OBJ:     $obj"
        log "  MTL:     $mtl"
        log "  Script:  blender -b -P $py"
        msg info "Escena exportada" "Archivos generados:\n\n$obj\n$mtl\n\nPara renderizar:\nblender -b -P $py"
        return ""
    }

    log "lanzando Blender headless ($blender_render_engine)..."
    set out [run_blender $py]
    set final $png
    if {[file exists $final]} {
        if {$file_format ne "png" && $file_format ne ""} {
            convert_to $final "${filename}.$file_format" $file_format
            if {[file exists "${filename}.$file_format"]} {
                set final "${filename}.$file_format"
            }
        }
        return $final
    }
    msg error "Error de Blender" "Blender no genero la imagen.\nRevisa la consola de VMD."
    return ""
}

# ----------------------------------------------------------------------------
# Render principal
# ----------------------------------------------------------------------------

proc ::Render2K::get_resolution {} {
    variable resolution_preset
    variable custom_width
    variable custom_height
    variable resolutions
    if {$resolution_preset eq "Custom"} {
        return [list $custom_width $custom_height]
    }
    return $resolutions($resolution_preset)
}

proc ::Render2K::validate_resolution {width height} {
    set normalized [list]
    foreach {label value} [list ancho $width alto $height] {
        if {![string is integer -strict $value] || [string index $value 0] eq "-"} {
            return -code error "El $label de resolución debe ser un entero positivo."
        }
        if {[string index $value 0] eq "+"} { set value [string range $value 1 end] }
        set value [string trimleft $value 0]
        if {$value eq ""} { set value 0 }
        if {$value == 0 || [string length $value] > 5 || $value > 32768} {
            return -code error "El $label de resolución debe estar entre 1 y 32768 px."
        }
        lappend normalized $value
    }
    return $normalized
}

proc ::Render2K::do_render {{eng ""} {outname ""}} {
    variable engine
    variable filename

    if {$eng ne "" && $eng ne "blender"} {
        msg error "Motor no soportado" "Blender Render solo renderiza con Blender."
        return ""
    }
    set engine "blender"
    if {$outname ne ""} { set filename $outname }

    if {![engine_available blender]} {
        msg error "Blender no disponible" "No se encontro el ejecutable Blender en PATH."
        return ""
    }

    if {[catch {set resolution [validate_resolution {*}[get_resolution]]} err]} {
        msg error "Resolucion invalida" $err
        return ""
    }
    foreach {width height} $resolution { break }

    if {$filename eq ""} {
        set filename "render2k_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
    }

    log "=========================================="
    log "RENDER Blender destino=${width}x${height} archivo=$filename"
    set t0 [clock seconds]

    set out [render_engine_blender $filename $width $height]

    set elapsed [expr {[clock seconds] - $t0}]
    if {$out ne "" && [file exists $out]} {
        log "=========================================="
        log "RENDERIZADO COMPLETADO en ${elapsed}s"
        log "  Archivo: [file join [pwd] $out]"
        log "=========================================="
        catch { exec xdg-open $out & }
        return [file join [pwd] $out]
    }
    log "RENDER fallido o cancelado (${elapsed}s)."
    return ""
}

proc ::Render2K::render2k {engine {width 1920} {height 1080} {outname ""}} {
    variable resolution_preset
    variable custom_width
    variable custom_height
    set saved_preset $resolution_preset
    set saved_w $custom_width
    set saved_h $custom_height
    set resolution_preset "Custom"
    set custom_width $width
    set custom_height $height
    set rc [do_render $engine $outname]
    set resolution_preset $saved_preset
    set custom_width $saved_w
    set custom_height $saved_h
    return $rc
}

proc render2k {args} {
    return [::Render2K::render2k {*}$args]
}

# ----------------------------------------------------------------------------
# Peliculas Blender
# ----------------------------------------------------------------------------

proc ::Render2K::movie_molid_value {} {
    variable movie_molid
    set requested [string trim $movie_molid]
    if {$requested eq "" || [string equal -nocase $requested "top"]} {
        set molid [molinfo top]
    } elseif {[string is integer -strict $requested]} {
        set molid $requested
    } else {
        return -code error "La molecula debe ser 'top' o un identificador numerico de VMD."
    }
    if {$molid < 0 || [catch {molinfo $molid get numframes}]} {
        return -code error "La molecula VMD '$requested' no esta disponible."
    }
    return $molid
}

proc ::Render2K::movie_paths {name} {
    if {[string trim $name] eq ""} {
        set name "render2k_movie_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
    }
    set requested [file normalize $name]
    if {[string equal -nocase [file extension $requested] ".mp4"]} {
        set root [file rootname $requested]
    } else {
        set root $requested
    }
    set dir "${root}_frames"
    return [dict create \
        output "${root}.mp4" \
        dir $dir \
        worker [file join $dir render2k_movie_worker.py] \
        manifest [file join $dir .render2k_movie.manifest] \
        lock [file join $dir .render2k_movie.lock] \
        temp_output [file join $dir .render2k_movie.part.mp4]]
}

proc ::Render2K::movie_job_paths {sequence vmd_frame} {
    variable movie_dir
    set stamp [format "%06d" $sequence]
    set base [file join $movie_dir "frame_$stamp"]
    return [dict create \
        sequence $sequence \
        vmd_frame $vmd_frame \
        obj "${base}.obj" \
        mtl "${base}.mtl" \
        py "${base}_blender.py" \
        image [file join $movie_dir "frame_${stamp}.png"]]
}

proc ::Render2K::movie_yield_for_cancel {} {
    variable movie_running
    variable movie_cancel_requested
    variable movie_stage
    # Solo se cede durante la fase VMD; fuera de una pelicula sigue siendo una
    # utilidad CRC normal y no debe despachar eventos inesperados.
    if {!$movie_running || $movie_stage ne "export"} { return 1 }
    catch { update }
    return [expr {$movie_running && !$movie_cancel_requested && $movie_stage eq "export"}]
}

proc ::Render2K::movie_file_crc {path} {
    if {![file exists $path] || ![file isfile $path]} { return "" }
    if {[catch {set fp [open $path rb]}]} { return "" }
    fconfigure $fp -translation binary -encoding binary
    set crc 0
    set rc [catch {
        while {![eof $fp]} {
            set data [read $fp 1048576]
            if {$data ne ""} { set crc [zlib crc32 $data $crc] }
            if {![movie_yield_for_cancel]} { error "CRC cancelado" }
        }
    }]
    catch {close $fp}
    if {$rc} { return "" }
    return [format "%08x" $crc]
}

# La reanudacion solo es segura si conserva el estado VMD que afecta el OBJ/MTL.
proc ::Render2K::movie_color_snapshot {} {
    set colors [list]
    set count 0
    catch { set count [colorinfo num] }
    for {set index 0} {$index < $count} {incr index} {
        set rgb ""
        catch { set rgb [colorinfo rgb $index] }
        lappend colors rgb $index $rgb
    }
    set methods [list]
    catch { set methods [lsort [colorinfo scale methods]] }
    foreach method $methods {
        set values ""
        catch { set values [color scale colors $method] }
        lappend colors scale $method $values
    }
    foreach option {method midpoint min max} {
        set value ""
        catch { set value [colorinfo scale $option] }
        lappend colors scale_option $option $value
    }
    set categories [list]
    catch { set categories [lsort [colorinfo categories]] }
    foreach category $categories {
        set names [list]
        catch { set names [lsort [colorinfo category $category]] }
        foreach name $names {
            set value ""
            catch { set value [colorinfo category $category $name] }
            lappend colors category $category $name $value
        }
    }
    return $colors
}

proc ::Render2K::movie_macro_snapshot {} {
    set macros [list]
    set names [list]
    catch { set names [lsort [atomselect macro]] }
    foreach name $names {
        set definition ""
        catch { set definition [atomselect macro $name] }
        lappend macros [list name $name definition $definition]
    }
    return $macros
}

proc ::Render2K::movie_molecule_snapshot {molid active_molid} {
    variable movie_source_crc_cache
    set name ""
    set atoms ""
    set frames_available ""
    set drawn 0
    catch { set name [molinfo $molid get name] }
    catch { set atoms [molinfo $molid get numatoms] }
    catch { set frames_available [molinfo $molid get numframes] }
    catch { set drawn [molinfo $molid get drawn] }
    set current_frame ""
    if {$molid != $active_molid} { catch { set current_frame [molinfo $molid get frame] } }

    set reps [list]
    set numreps 0
    catch { set numreps [molinfo $molid get numreps] }
    set clipplanes 0
    catch { set clipplanes [mol clipplane num] }
    for {set index 0} {$index < $numreps} {incr index} {
        set config ""
        set periodic ""
        set periodic_count ""
        set visible ""
        set selupdate ""
        set colupdate ""
        set range ""
        set smooth ""
        set frames ""
        catch { set config [molinfo $molid get "{rep $index} {selection $index} {color $index} {material $index}"] }
        catch { set periodic [mol showperiodic $molid $index] }
        catch { set periodic_count [mol numperiodic $molid $index] }
        catch { set visible [mol showrep $molid $index] }
        catch { set selupdate [mol selupdate $index $molid] }
        catch { set colupdate [mol colupdate $index $molid] }
        catch { set range [mol scaleminmax $molid $index] }
        catch { set smooth [mol smoothrep $molid $index] }
        catch { set frames [mol drawframes $molid $index] }
        set clipping [list]
        for {set plane 0} {$plane < $clipplanes} {incr plane} {
            set values [list]
            foreach field {center color normal status} {
                set value ""
                catch { set value [mol clipplane $field $plane $index $molid] }
                lappend values $field $value
            }
            lappend clipping $values
        }
        lappend reps [list index $index config $config periodic $periodic \
            periodic_count $periodic_count visible $visible selupdate $selupdate \
            colupdate $colupdate range $range smooth $smooth frames $frames \
            clipping $clipping]
    }

    set transforms [list]
    foreach field {center_matrix rotate_matrix scale_matrix global_matrix} {
        set value ""
        catch { set value [molinfo $molid get $field] }
        lappend transforms $field $value
    }
    set graphics [list]
    set graphic_ids [list]
    catch { set graphic_ids [graphics $molid list] }
    foreach graphic_id $graphic_ids {
        set graphic ""
        catch { set graphic [graphics $molid info $graphic_id] }
        lappend graphics $graphic
    }
    set volume_data 0
    catch { set volume_data [molinfo $molid get numvolumedata] }
    set sources [list]
    set filename_values [list]
    catch { set filename_values [molinfo $molid get filename] }
    set filenames $filename_values
    if {[llength $filename_values] == 1} { set filenames [lindex $filename_values 0] }
    foreach filename $filenames {
        set record [list path $filename]
        if {$filename ne "" && [file exists $filename] && [file isfile $filename]} {
            set normalized [file normalize $filename]
            set size [file size $filename]
            set mtime [file mtime $filename]
            lappend record normalized $normalized size $size mtime $mtime
            if {$volume_data > 0} {
                set cache_key [list $normalized $size $mtime]
                if {[dict exists $movie_source_crc_cache $cache_key]} {
                    set crc [dict get $movie_source_crc_cache $cache_key]
                } else {
                    set crc [movie_file_crc $filename]
                    if {$crc eq ""} {
                        return -code error "No se pudo verificar la fuente de volumen $filename."
                    }
                    dict set movie_source_crc_cache $cache_key $crc
                }
                lappend record crc $crc
            }
        }
        lappend sources $record
    }
    return [list name $name atoms $atoms frames_available $frames_available \
        drawn $drawn current_frame $current_frame reps $reps transforms $transforms \
        graphics $graphics volume_data $volume_data sources $sources]
}

proc ::Render2K::movie_scene_snapshot {active_molid} {
    set molecules [list]
    set molids [list]
    catch { set molids [lsort -integer [molinfo list]] }
    foreach molid $molids {
        lappend molecules [movie_molecule_snapshot $molid $active_molid]
    }
    return [list molecules $molecules colors [movie_color_snapshot] macros [movie_macro_snapshot]]
}

proc ::Render2K::movie_signature {molecule_name atoms numframes specs width height camera settings scene} {
    set payload [list \
        format Render2KMovie-6 \
        molecule $molecule_name \
        atoms $atoms \
        frames_available $numframes \
        frames_selected $specs \
        resolution [list $width $height] \
        camera $camera \
        blender $settings \
        scene $scene]
    return [format "%08x" [zlib crc32 $payload]]
}

proc ::Render2K::movie_molecule_render_frames {molid current_frame} {
    set frames [dict create $current_frame 1]
    set total [molinfo $molid get numframes]
    set numreps [molinfo $molid get numreps]
    for {set rep 0} {$rep < $numreps} {incr rep} {
        set visible 1
        catch { set visible [mol showrep $molid $rep] }
        if {!$visible} { continue }
        set drawframes now
        catch { set drawframes [string trim [mol drawframes $molid $rep]] }
        if {$drawframes eq "" || $drawframes eq "now"} { continue }
        if {$drawframes eq "all"} {
            for {set frame 0} {$frame < $total} {incr frame} { dict set frames $frame 1 }
            continue
        }
        set known_frames 1
        foreach frame $drawframes {
            if {![string is integer -strict $frame] || $frame < 0 || $frame >= $total} {
                set known_frames 0
                break
            }
            dict set frames $frame 1
        }
        if {!$known_frames} {
            # Un formato de drawframes no reconocido se trata como "all".
            for {set frame 0} {$frame < $total} {incr frame} { dict set frames $frame 1 }
        }
    }
    return [lsort -integer [dict keys $frames]]
}

proc ::Render2K::movie_molecule_frame_state_crc {molid frame atom_count} {
    set crc [zlib crc32 [list molecule $molid frame $frame] 0]
    set chunk_size 8192
    set base_fields {x y z beta occupancy user charge mass radius name type element structure resname resid chain segname}
    set optional_fields {user2 user3 user4 atomicnumber altloc insertion vx vy vz color fragment}
    for {set first 0} {$first < $atom_count} {incr first $chunk_size} {
        set last [expr {min($atom_count - 1, $first + $chunk_size - 1)}]
        if {[catch {set sel [atomselect $molid "index $first to $last" frame $frame]} err]} {
            return -code error "No se pudieron leer los átomos de la molécula $molid: $err"
        }
        set rc [catch {set values [$sel get $base_fields]} err]
        if {!$rc} { set crc [zlib crc32 [list atoms $first $values] $crc] }
        foreach field $optional_fields {
            if {![catch {set values [$sel get $field]}]} {
                set crc [zlib crc32 [list $field $first $values] $crc]
            }
        }
        if {![catch {set bonds [$sel getbonds]}]} {
            set crc [zlib crc32 [list bonds $first $bonds] $crc]
        }
        if {![catch {set bondorders [$sel getbondorders]}]} {
            set crc [zlib crc32 [list bondorders $first $bondorders] $crc]
        }
        catch { $sel delete }
        if {$rc} {
            return -code error "No se pudieron leer los átomos de la molécula $molid: $err"
        }
        if {![movie_yield_for_cancel]} {
            return -code error "La pelicula fue cancelada."
        }
    }
    # molinfo devuelve la celda del frame activo, no del frame del atomselect.
    set cell ""
    set original_frame ""
    set switched_frame 0
    catch { set original_frame [molinfo $molid get frame] }
    if {[string is integer -strict $original_frame] && $original_frame != $frame} {
        if {![catch {molinfo $molid set frame $frame}]} { set switched_frame 1 }
    }
    catch { set cell [molinfo $molid get {a b c alpha beta gamma}] }
    if {$switched_frame} { catch {molinfo $molid set frame $original_frame} }
    set crc [zlib crc32 [list cell $cell] $crc]
    return [format "%08x" $crc]
}

# Cada job conserva los datos atómicos y topológicos de la escena visible.
proc ::Render2K::movie_frame_state_crc {} {
    set payload [list]
    set molids [lsort -integer [molinfo list]]
    foreach molid $molids {
        set drawn [molinfo $molid get drawn]
        if {!$drawn} { continue }
        set atoms [molinfo $molid get numatoms]
        set current_frame [molinfo $molid get frame]
        foreach frame [movie_molecule_render_frames $molid $current_frame] {
            set crc [movie_molecule_frame_state_crc $molid $frame $atoms]
            lappend payload [list molecule $molid frame $frame atoms $atoms state $crc]
        }
    }
    return [format "%08x" [zlib crc32 $payload]]
}

proc ::Render2K::movie_manifest_read {path} {
    if {![file exists $path] || [catch {set fp [open $path r]}]} { return [dict create] }
    set header ""
    catch { set header [gets $fp] }
    set encoded [string map [list "\n" "" "\r" ""] [read $fp]]
    close $fp
    if {$header ne "R2K_MOVIE_MANIFEST 1" || $encoded eq ""} { return [dict create] }
    if {[catch {set data [binary decode base64 $encoded]}]} { return [dict create] }
    if {[catch {dict size $data}]} { return [dict create] }
    return $data
}

proc ::Render2K::movie_manifest_write {path data} {
    set encoded [string map [list "\n" "" "\r" ""] [binary encode base64 $data]]
    set tmp "${path}.[clock clicks].tmp"
    set fp [open $tmp w]
    puts $fp "R2K_MOVIE_MANIFEST 1"
    puts $fp $encoded
    close $fp
    file rename -force $tmp $path
    return 1
}

proc ::Render2K::movie_write_manifest {} {
    variable movie_manifest
    variable movie_signature
    variable movie_total
    variable movie_manifest_jobs
    return [movie_manifest_write $movie_manifest [dict create \
        format 1 signature $movie_signature total $movie_total jobs $movie_manifest_jobs]]
}

proc ::Render2K::movie_job_record {job} {
    foreach {key path} [list obj [dict get $job obj] mtl [dict get $job mtl] py [dict get $job py]] {
        if {![file exists $path] || ![file isfile $path]} {
            return -code error "Falta el asset $key para el frame VMD [dict get $job vmd_frame]."
        }
    }
    set record [dict create vmd_frame [dict get $job vmd_frame]]
    foreach {key path} [list obj [dict get $job obj] mtl [dict get $job mtl] py [dict get $job py]] {
        set crc [movie_file_crc $path]
        if {$crc eq ""} { return -code error "No se pudo verificar el asset Blender $path." }
        dict set record ${key}_size [file size $path]
        dict set record ${key}_crc $crc
    }
    if {[dict exists $job camera]} { dict set record camera [dict get $job camera] }
    if {[dict exists $job state_crc]} { dict set record state_crc [dict get $job state_crc] }
    return $record
}

proc ::Render2K::movie_record_job {job} {
    variable movie_manifest_jobs
    dict set movie_manifest_jobs [dict get $job sequence] [movie_job_record $job]
    movie_write_manifest
}

proc ::Render2K::movie_manifest_job_matches {job} {
    variable movie_manifest_jobs
    set sequence [dict get $job sequence]
    if {![dict exists $movie_manifest_jobs $sequence]} { return 0 }
    set record [dict get $movie_manifest_jobs $sequence]
    foreach key {vmd_frame obj_size obj_crc mtl_size mtl_crc py_size py_crc} {
        if {![dict exists $record $key]} { return 0 }
    }
    if {[dict get $record vmd_frame] != [dict get $job vmd_frame]} { return 0 }
    if {[dict exists $job camera]} {
        if {![dict exists $record camera] ||
                ![string equal [dict get $record camera] [dict get $job camera]]} { return 0 }
    }
    if {[dict exists $job state_crc]} {
        if {![dict exists $record state_crc] ||
                ![string equal [dict get $record state_crc] [dict get $job state_crc]]} { return 0 }
    }
    foreach {key path} [list obj [dict get $job obj] mtl [dict get $job mtl] py [dict get $job py]] {
        if {![file exists $path] || ![file isfile $path]} { return 0 }
        if {[file size $path] != [dict get $record ${key}_size]} { return 0 }
        if {![string equal [movie_file_crc $path] [dict get $record ${key}_crc]]} { return 0 }
    }
    return 1
}

proc ::Render2K::movie_manifest_image_matches {job} {
    variable movie_manifest_jobs
    set sequence [dict get $job sequence]
    if {![dict exists $movie_manifest_jobs $sequence]} { return 0 }
    set record [dict get $movie_manifest_jobs $sequence]
    set image [dict get $job image]
    foreach key {vmd_frame image_size image_crc} {
        if {![dict exists $record $key]} { return 0 }
    }
    if {[dict get $record vmd_frame] != [dict get $job vmd_frame]} {
        return 0
    }
    if {[dict exists $job camera]} {
        if {![dict exists $record camera] ||
                ![string equal [dict get $record camera] [dict get $job camera]]} { return 0 }
    }
    if {[dict exists $job state_crc]} {
        if {![dict exists $record state_crc] ||
                ![string equal [dict get $record state_crc] [dict get $job state_crc]]} { return 0 }
    }
    if {![file exists $image] || ![file isfile $image]} { return 0 }
    if {[file size $image] != [dict get $record image_size]} { return 0 }
    return [string equal [movie_file_crc $image] [dict get $record image_crc]]
}

proc ::Render2K::movie_record_images {jobs} {
    variable movie_manifest_jobs
    foreach job $jobs {
        set sequence [dict get $job sequence]
        if {![dict exists $movie_manifest_jobs $sequence]} {
            return -code error "No hay registro de assets para el frame VMD [dict get $job vmd_frame]."
        }
        set image [dict get $job image]
        if {![file exists $image] || ![file isfile $image] || [file size $image] <= 0} {
            return -code error "No se pudo verificar el PNG del frame VMD [dict get $job vmd_frame]."
        }
        set crc [movie_file_crc $image]
        if {$crc eq ""} {
            return -code error "No se pudo calcular la integridad del PNG $image."
        }
        dict set movie_manifest_jobs $sequence image_size [file size $image]
        dict set movie_manifest_jobs $sequence image_crc $crc
    }
    movie_write_manifest
}

proc ::Render2K::movie_directory_has_data {dir} {
    foreach pattern {* .*} {
        foreach path [glob -nocomplain -directory $dir $pattern] {
            set name [file tail $path]
            if {$name ni {. .. .render2k_movie.lock}} { return 1 }
        }
    }
    return 0
}

proc ::Render2K::movie_acquire_lock {} {
    variable movie_lock
    if {[catch {file mkdir $movie_lock} err]} {
        return -code error "El lote ya esta bloqueado por otro proceso o quedo un bloqueo pendiente: $movie_lock"
    }
    return 1
}

proc ::Render2K::movie_release_lock {} {
    variable movie_lock
    if {$movie_lock ne "" && [file exists $movie_lock]} { catch {file delete -force $movie_lock} }
    set movie_lock ""
}

proc ::Render2K::movie_remove_known_assets {} {
    variable movie_frame_specs
    variable movie_worker
    variable movie_manifest
    foreach spec $movie_frame_specs {
        foreach {sequence vmd_frame} $spec { break }
        set job [movie_job_paths $sequence $vmd_frame]
        foreach key {obj mtl py image} { catch {file delete -force [dict get $job $key]} }
    }
    catch {file delete -force $movie_worker}
    catch {file delete -force $movie_manifest}
}

proc ::Render2K::movie_reset_known_assets {} {
    variable movie_manifest_jobs
    movie_remove_known_assets
    set movie_manifest_jobs [dict create]
    movie_write_manifest
}

proc ::Render2K::movie_prepare_assets {} {
    variable movie_manifest
    variable movie_signature
    variable movie_total
    variable movie_manifest_jobs
    variable movie_dir
    variable movie_run_options
    set existing [movie_manifest_read $movie_manifest]
    if {[dict size $existing] == 0} {
        if {[movie_directory_has_data $movie_dir]} {
            return -code error "El directorio de assets existe pero no pertenece a este lote: $movie_dir"
        }
        set movie_manifest_jobs [dict create]
        return [movie_write_manifest]
    }
    foreach key {format signature total jobs} {
        if {![dict exists $existing $key]} {
            return -code error "El manifiesto de pelicula no es valido: $movie_manifest"
        }
    }
    if {[dict get $existing format] != 1 || [dict get $existing signature] ne $movie_signature ||
            [dict get $existing total] != $movie_total} {
        return -code error "Los assets existentes pertenecen a otra pelicula; elige otro archivo de salida."
    }
    set movie_manifest_jobs [dict get $existing jobs]
    if {![dict get $movie_run_options resume]} { movie_reset_known_assets }
    return 1
}

proc ::Render2K::movie_restore_frame {} {
    variable movie_active_molid
    variable movie_original_frame
    if {$movie_active_molid >= 0 && $movie_original_frame ne ""} {
        catch { molinfo $movie_active_molid set frame $movie_original_frame }
        catch { display update }
    }
    set movie_original_frame ""
}

proc ::Render2K::movie_update_controls {} {
    variable w
    variable movie_running
    variable movie_cancel_requested
    if {$w eq "" || [llength [info commands winfo]] == 0} { return }
    set start "$w.main.v.actions.start"
    set cancel "$w.main.v.actions.cancel"
    if {[catch {winfo exists $start} exists] || !$exists} { return }
    $start configure -state [expr {$movie_running ? "disabled" : "normal"}]
    if {[winfo exists $cancel]} {
        $cancel configure -state [expr {$movie_running && !$movie_cancel_requested ? "normal" : "disabled"}]
    }
}

proc ::Render2K::movie_finish_cancel {} {
    variable movie_after
    variable movie_cancel_after
    variable movie_running
    variable movie_cancel_requested
    variable movie_stage
    variable movie_pipe
    variable movie_process_kind
    variable movie_status
    variable movie_progress_text
    variable movie_temp_output
    if {$movie_after ne ""} { catch { after cancel $movie_after } }
    set movie_after ""
    if {$movie_cancel_after ne ""} { catch { after cancel $movie_cancel_after } }
    set movie_cancel_after ""
    movie_restore_frame
    set movie_running 0
    set movie_cancel_requested 0
    set movie_stage ""
    set movie_pipe ""
    set movie_process_kind ""
    if {$movie_temp_output ne "" && [file exists $movie_temp_output]} {
        catch {file delete -force $movie_temp_output}
    }
    movie_release_lock
    set movie_status "Película cancelada. Los assets se conservaron para reanudar."
    set movie_progress_text "Cancelada"
    log "PELÍCULA cancelada; los frames y escenas parciales se conservaron."
    movie_update_controls
}

proc ::Render2K::movie_fail {reason} {
    variable movie_after
    variable movie_cancel_after
    variable movie_running
    variable movie_cancel_requested
    variable movie_stage
    variable movie_pipe
    variable movie_process_kind
    variable movie_status
    variable movie_progress_text
    variable movie_temp_output
    if {$movie_after ne ""} { catch { after cancel $movie_after } }
    set movie_after ""
    if {$movie_cancel_after ne ""} { catch { after cancel $movie_cancel_after } }
    set movie_cancel_after ""
    movie_restore_frame
    set movie_running 0
    set movie_cancel_requested 0
    set movie_stage ""
    set movie_pipe ""
    set movie_process_kind ""
    if {$movie_temp_output ne "" && [file exists $movie_temp_output]} {
        catch {file delete -force $movie_temp_output}
    }
    movie_release_lock
    set movie_status "Error: $reason"
    set movie_progress_text "Fallida"
    log "PELÍCULA fallida: $reason"
    movie_update_controls
    msg error "Error de pelicula Blender" "$reason\n\nLos assets se conservaron para diagnostico o reanudacion."
}

proc ::Render2K::movie_all_images {} {
    variable movie_jobs
    foreach job $movie_jobs {
        set image [dict get $job image]
        if {![file exists $image] || [file size $image] <= 0} { return 0 }
    }
    return 1
}

# El worker ejecuta los scripts por frame dentro de una sola instancia Blender.
# Cada script reinicia la escena, por lo que no acumula geometria de QuickSurf.
proc ::Render2K::gen_blender_movie_py {pyscript jobs} {
    set py [open $pyscript w]
    puts $py "# Auto-generado por Render2K Blender: worker de pelicula"
    puts $py {JOBS = [}
    foreach job $jobs {
        puts $py [format "    (%d, %s)," [dict get $job vmd_frame] [py_quote [dict get $job py]]]
    }
    puts $py "]"
    puts $py ""
    puts $py {for position, (vmd_frame, script_path) in enumerate(JOBS, 1):}
    puts $py {    print("R2K_FRAME: %d/%d VMD=%d" % (position, len(JOBS), vmd_frame), flush=True)}
    puts $py {    namespace = {"__name__": "__main__", "__file__": script_path}}
    puts $py {    with open(script_path, "r", encoding="utf-8") as handle:}
    puts $py {        exec(compile(handle.read(), script_path, "exec"), namespace)}
    puts $py {    print("R2K_FRAME_DONE: %d/%d VMD=%d" % (position, len(JOBS), vmd_frame), flush=True)}
    puts $py {print("R2K_MOVIE_BLENDER_DONE", flush=True)}
    close $py
    return 1
}

proc ::Render2K::movie_start_process {kind command} {
    variable movie_pipe
    variable movie_process_kind
    lappend command 2>@1
    if {[catch {set pipe [open "|$command" r]} err]} {
        movie_fail "No se pudo iniciar $kind: $err"
        return 0
    }
    fconfigure $pipe -blocking 0 -buffering line -translation auto
    set movie_pipe $pipe
    set movie_process_kind $kind
    fileevent $pipe readable [list ::Render2K::movie_process_readable $pipe $kind]
    return 1
}

proc ::Render2K::movie_process_readable {pipe kind} {
    variable movie_pipe
    variable movie_process_kind
    variable movie_cancel_requested
    variable movie_render_total
    variable movie_worker_complete
    variable movie_rendered_jobs
    variable movie_pending
    variable movie_progress
    variable movie_progress_text
    variable movie_status
    if {$pipe ne $movie_pipe} { return }

    while {[gets $pipe line] >= 0} {
        log "$kind: $line"
        if {$kind eq "blender" && [regexp {^R2K_FRAME: ([0-9]+)/([0-9]+) VMD=([-0-9]+)} $line -> current total vmd_frame]} {
            set movie_status "Blender renderiza frame VMD $vmd_frame ($current/$total)"
            set movie_progress_text "Blender: $current/$total"
        }
        if {$kind eq "blender" && [regexp {^R2K_FRAME_DONE: ([0-9]+)/([0-9]+)} $line -> done total]} {
            if {$movie_render_total > 0} {
                set movie_progress [expr {45.0 + 45.0 * $done / double($movie_render_total)}]
            }
            dict set movie_rendered_jobs $done 1
            set movie_progress_text "Blender: $done/$total"
        }
        if {$kind eq "blender" && $line eq "R2K_MOVIE_BLENDER_DONE"} {
            set movie_worker_complete 1
        }
    }
    if {![eof $pipe]} { return }

    fileevent $pipe readable {}
    set movie_pipe ""
    set movie_process_kind ""
    set failed [catch {close $pipe} err]
    if {$movie_cancel_requested} {
        movie_finish_cancel
        return
    }
    if {$failed} {
        movie_fail "$kind termino con error: $err"
        return
    }
    if {$kind eq "blender"} {
        if {!$movie_worker_complete || [dict size $movie_rendered_jobs] != $movie_render_total} {
            movie_fail "Blender no confirmo todos los frames del lote."
            return
        }
        if {![movie_all_images]} {
            movie_fail "Blender termino sin producir todos los PNG de la secuencia."
            return
        }
        if {[catch {movie_record_images $movie_pending} err]} {
            movie_fail "No se pudo registrar la integridad de los PNG: $err"
            return
        }
        movie_start_encoding
    } elseif {$kind eq "ffmpeg"} {
        movie_finish_success
    }
}

proc ::Render2K::movie_start_blender {} {
    variable have_blender
    variable movie_running
    variable movie_run_id
    variable movie_stage
    variable movie_pending
    variable movie_render_total
    variable movie_worker_complete
    variable movie_rendered_jobs
    variable movie_worker
    variable movie_status
    variable movie_progress
    variable movie_progress_text
    set run_id $movie_run_id
    if {[llength $movie_pending] == 0} {
        movie_start_encoding
        return
    }
    foreach job $movie_pending {
        set matches [movie_manifest_job_matches $job]
        if {$run_id != $movie_run_id || !$movie_running || $movie_stage ne "export"} { return }
        if {!$matches} {
            movie_fail "Los assets de un frame pendiente no coinciden con el manifiesto."
            return
        }
    }
    if {[catch {gen_blender_movie_py $movie_worker $movie_pending} err]} {
        movie_fail "No se pudo generar el worker Blender: $err"
        return
    }
    set movie_render_total [llength $movie_pending]
    set movie_worker_complete 0
    set movie_rendered_jobs [dict create]
    set movie_stage "blender"
    set movie_status "Blender renderiza $movie_render_total frame(s) en un unico lote."
    set movie_progress 45
    set movie_progress_text "Blender: 0/$movie_render_total"
    log "PELÍCULA: iniciando un unico proceso Blender para $movie_render_total frame(s)."
    movie_start_process blender [list $have_blender -b --python-exit-code 1 -P $movie_worker]
}

proc ::Render2K::movie_start_encoding {} {
    variable have_ffmpeg
    variable movie_run_options
    variable movie_dir
    variable movie_total
    variable movie_temp_output
    variable movie_stage
    variable movie_status
    variable movie_progress
    variable movie_progress_text
    variable movie_cancel_requested
    if {$movie_cancel_requested} {
        movie_finish_cancel
        return
    }
    if {![movie_all_images]} {
        movie_fail "Faltan PNG en la secuencia; no se codificara un MP4 incompleto."
        return
    }
    set movie_stage "ffmpeg"
    set movie_status "FFmpeg codifica el MP4 H.264..."
    set movie_progress 92
    set movie_progress_text "Codificando MP4"
    set fps [dict get $movie_run_options fps]
    set crf [dict get $movie_run_options crf]
    set input [file join $movie_dir "frame_%06d.png"]
    set filter "pad=ceil(iw/2)*2:ceil(ih/2)*2"
    catch {file delete -force $movie_temp_output}
    set command [list $have_ffmpeg -y -hide_banner -loglevel error \
        -framerate $fps -start_number 1 -i $input -frames:v $movie_total \
        -vf $filter -c:v libx264 -preset medium -crf $crf \
        -pix_fmt yuv420p -movflags +faststart $movie_temp_output]
    log "PELÍCULA: codificando MP4 con FFmpeg a $movie_temp_output"
    movie_start_process ffmpeg $command
}

proc ::Render2K::movie_finish_success {} {
    variable movie_run_options
    variable movie_output
    variable movie_temp_output
    variable movie_running
    variable movie_cancel_requested
    variable movie_stage
    variable movie_status
    variable movie_progress
    variable movie_progress_text
    if {![file exists $movie_temp_output]} {
        movie_fail "FFmpeg termino sin generar el MP4 temporal."
        return
    }
    if {[file exists $movie_output]} {
        if {[file isdirectory $movie_output]} {
            movie_fail "La ruta MP4 final es un directorio y no se puede publicar la película."
            return
        }
        if {![dict get $movie_run_options overwrite]} {
            movie_fail "El MP4 final apareció durante el render y no se sobrescribirá sin autorización."
            return
        }
    }
    if {[dict get $movie_run_options overwrite]} {
        if {[catch {file rename -force $movie_temp_output $movie_output} err]} {
            movie_fail "No se pudo publicar el MP4 final: $err"
            return
        }
    } else {
        # link(2) crea el destino solamente si aún no existe; evita el hueco
        # entre la comprobación anterior y un rename -force.
        if {[catch {file link -hard $movie_output $movie_temp_output} err]} {
            if {[file exists $movie_output]} {
                movie_fail "El MP4 final apareció durante el render y no se sobrescribirá sin autorización."
            } else {
                movie_fail "No se pudo publicar el MP4 final sin sobrescribir: $err"
            }
            return
        }
        if {[catch {file delete -force $movie_temp_output} err]} {
            log "ADVERTENCIA: no se pudo limpiar el MP4 temporal publicado: $err"
        }
    }
    if {[file isdirectory $movie_output]} {
        catch {file delete -force [file join $movie_output [file tail $movie_temp_output]]}
        movie_fail "La ruta MP4 se convirtió en un directorio durante la publicación."
        return
    }
    if {![file exists $movie_output] || ![file isfile $movie_output]} {
        movie_fail "No se pudo verificar el MP4 publicado."
        return
    }
    movie_restore_frame
    set movie_running 0
    set movie_cancel_requested 0
    set movie_stage ""
    set movie_progress 100
    set movie_progress_text "Completada"
    set movie_status "Película completada: $movie_output"
    if {![dict get $movie_run_options keep_assets]} {
        movie_remove_known_assets
        append movie_status " (assets limpiados)"
    }
    movie_release_lock
    log "PELÍCULA COMPLETADA: $movie_output"
    movie_update_controls
    catch { exec xdg-open $movie_output & }
}

proc ::Render2K::movie_signal_process {signal} {
    variable movie_pipe
    if {$movie_pipe eq ""} { return }
    if {![catch {pid $movie_pipe} processes]} {
        foreach process $processes { catch { exec kill -$signal $process } }
    }
}

proc ::Render2K::movie_force_cancel {pipe} {
    variable movie_running
    variable movie_cancel_requested
    variable movie_pipe
    variable movie_cancel_after
    variable movie_status
    set movie_cancel_after ""
    if {!$movie_running || !$movie_cancel_requested || $pipe ne $movie_pipe} { return }
    set movie_status "Forzando cancelacion de pelicula..."
    movie_signal_process KILL
}

proc ::Render2K::cancel_movie {{force 0}} {
    variable movie_running
    variable movie_cancel_requested
    variable movie_stage
    variable movie_after
    variable movie_pipe
    variable movie_cancel_after
    variable movie_status
    if {!$movie_running} { return 0 }
    if {$movie_cancel_requested && !$force} { return 1 }
    set movie_cancel_requested 1
    set movie_status "Cancelando pelicula..."
    movie_update_controls
    if {$movie_stage eq "export"} {
        if {$movie_after ne ""} { catch { after cancel $movie_after } }
        set movie_after ""
        movie_finish_cancel
        return 1
    }
    if {$movie_pipe ne ""} {
        set pipe $movie_pipe
        movie_signal_process TERM
        if {!$force} {
            if {$movie_cancel_after ne ""} { catch { after cancel $movie_cancel_after } }
            set movie_cancel_after [after 2000 [list ::Render2K::movie_force_cancel $pipe]]
            return 1
        }
        fileevent $pipe readable {}
        movie_signal_process KILL
        catch { close $pipe }
        set movie_pipe ""
    }
    movie_finish_cancel
    return 1
}

proc ::Render2K::movie_export_next {} {
    variable movie_running
    variable movie_run_id
    variable movie_cancel_requested
    variable movie_stage
    variable movie_after
    variable movie_frame_specs
    variable movie_index
    variable movie_total
    variable movie_jobs
    variable movie_pending
    variable movie_run_options
    variable movie_active_molid
    variable movie_camera
    variable movie_settings
    variable movie_scene
    variable movie_width
    variable movie_height
    variable movie_progress
    variable movie_progress_text
    variable movie_status
    set movie_after ""
    if {!$movie_running || $movie_stage ne "export"} { return }
    set run_id $movie_run_id
    if {$movie_cancel_requested} {
        movie_finish_cancel
        return
    }
    if {$movie_index >= $movie_total} {
        movie_export_complete
        return
    }

    foreach {sequence vmd_frame} [lindex $movie_frame_specs $movie_index] { break }
    set job [movie_job_paths $sequence $vmd_frame]
    if {[catch {molinfo $movie_active_molid set frame $vmd_frame} err]} {
        movie_fail "No se pudo activar el frame VMD $vmd_frame: $err"
        return
    }
    catch { display update }
    set scene_rc [catch {set current_scene [movie_scene_snapshot $movie_active_molid]} err]
    if {$run_id != $movie_run_id || !$movie_running || $movie_stage ne "export"} { return }
    if {$scene_rc} {
        movie_fail "No se pudo verificar la escena VMD del frame $vmd_frame: $err"
        return
    }
    if {$current_scene ne $movie_scene} {
        movie_fail "La escena VMD cambió durante el lote; no se mezclarán frames con estados distintos."
        return
    }
    if {[dict size $movie_camera] == 0} {
        dict set job camera [blender_camera_snapshot]
    } else {
        dict set job camera $movie_camera
    }
    set state_rc [catch {dict set job state_crc [movie_frame_state_crc]} err]
    if {$run_id != $movie_run_id || !$movie_running || $movie_stage ne "export"} { return }
    if {$state_rc} {
        movie_fail "No se pudo verificar el estado del frame VMD $vmd_frame: $err"
        return
    }
    set scene_rc [catch {set current_scene [movie_scene_snapshot $movie_active_molid]} err]
    if {$run_id != $movie_run_id || !$movie_running || $movie_stage ne "export"} { return }
    if {$scene_rc} {
        movie_fail "No se pudo verificar la escena VMD del frame $vmd_frame: $err"
        return
    }
    if {$current_scene ne $movie_scene} {
        movie_fail "La escena VMD cambió durante el lote; no se mezclarán frames con estados distintos."
        return
    }
    lappend movie_jobs $job
    set obj [dict get $job obj]

    set position [expr {$movie_index + 1}]
    set image_matches 0
    if {[dict get $movie_run_options resume]} {
        set image_matches [movie_manifest_image_matches $job]
        if {$run_id != $movie_run_id || !$movie_running || $movie_stage ne "export"} { return }
    }
    if {$image_matches} {
        set movie_status "Frame VMD $vmd_frame ya esta renderizado ($position/$movie_total)."
        log "PELÍCULA: se reutiliza PNG del frame VMD $vmd_frame."
    } else {
        set asset_matches 0
        if {[dict get $movie_run_options resume]} {
            set asset_matches [movie_manifest_job_matches $job]
            if {$run_id != $movie_run_id || !$movie_running || $movie_stage ne "export"} { return }
        }
        if {$asset_matches} {
            set movie_status "Se reanuda escena VMD $vmd_frame ($position/$movie_total)."
            lappend movie_pending $job
            log "PELÍCULA: se reutilizan assets del frame VMD $vmd_frame."
        } else {
            set movie_status "Exportando frame VMD $vmd_frame ($position/$movie_total)..."
            if {[catch {export_blender_frame [file rootname $obj] $movie_width $movie_height \
                    [dict get $job camera] $movie_settings} err]} {
                movie_fail "No se pudo exportar el frame VMD $vmd_frame: $err"
                return
            }
            set record_rc [catch {movie_record_job $job} err]
            if {$run_id != $movie_run_id || !$movie_running || $movie_stage ne "export"} { return }
            if {$record_rc} {
                movie_fail "No se pudo registrar el frame VMD $vmd_frame: $err"
                return
            }
            lappend movie_pending $job
        }
    }
    incr movie_index
    set movie_progress [expr {45.0 * $movie_index / double($movie_total)}]
    set movie_progress_text "VMD: $movie_index/$movie_total"
    set movie_after [after 1 [list ::Render2K::movie_export_next]]
}

proc ::Render2K::movie_export_complete {} {
    variable movie_cancel_requested
    variable movie_pending
    variable movie_status
    variable movie_progress
    variable movie_progress_text
    if {$movie_cancel_requested} {
        movie_finish_cancel
        return
    }
    movie_restore_frame
    set movie_progress 45
    if {[llength $movie_pending] == 0} {
        set movie_status "Todos los PNG ya existen; se codificara el MP4."
        set movie_progress_text "PNG reutilizados"
        movie_start_encoding
    } else {
        set movie_status "Exportacion VMD completada; preparando Blender."
        set movie_progress_text "VMD completado"
        movie_start_blender
    }
}

proc ::Render2K::do_movie {} {
    variable have_blender
    variable have_ffmpeg
    variable movie_running
    variable movie_run_id
    variable movie_molid
    variable movie_start
    variable movie_end
    variable movie_stride
    variable movie_fps
    variable movie_crf
    variable movie_filename
    variable movie_resume
    variable movie_keep_assets
    variable movie_lock_camera
    variable movie_overwrite
    variable movie_active_molid
    variable movie_original_frame
    variable movie_camera
    variable movie_settings
    variable movie_scene
    variable movie_source_crc_cache
    variable movie_run_options
    variable movie_output
    variable movie_temp_output
    variable movie_dir
    variable movie_worker
    variable movie_manifest
    variable movie_lock
    variable movie_signature
    variable movie_manifest_jobs
    variable movie_width
    variable movie_height
    variable movie_frame_specs
    variable movie_jobs
    variable movie_pending
    variable movie_index
    variable movie_total
    variable movie_render_total
    variable movie_worker_complete
    variable movie_rendered_jobs
    variable movie_cancel_requested
    variable movie_stage
    variable movie_pipe
    variable movie_process_kind
    variable movie_after
    variable movie_cancel_after
    variable movie_status
    variable movie_progress
    variable movie_progress_text

    if {$movie_running} {
        msg info "Película en curso" "Ya hay una película Blender en proceso."
        return ""
    }
    if {[blender_material_editor_open] && ![save_blender_material]} { return "" }
    if {![engine_available blender]} {
        msg error "Blender no disponible" "No se encontro el ejecutable Blender en PATH."
        return ""
    }
    if {$have_ffmpeg eq 0 || $have_ffmpeg eq ""} {
        msg error "FFmpeg no disponible" "Se necesita ffmpeg para codificar la secuencia PNG a MP4."
        return ""
    }
    if {![string is integer -strict $movie_start] || ![string is integer -strict $movie_end] ||
            ![string is integer -strict $movie_stride] || $movie_stride <= 0} {
        msg error "Rango de frames invalido" "Inicio, final y salto deben ser enteros; el salto debe ser mayor que cero."
        return ""
    }
    if {![string is integer -strict $movie_fps] || $movie_fps < 1 || $movie_fps > 240} {
        msg error "FPS invalido" "Configura entre 1 y 240 FPS."
        return ""
    }
    if {![string is integer -strict $movie_crf] || $movie_crf < 0 || $movie_crf > 51} {
        msg error "CRF invalido" "CRF debe estar entre 0 y 51; 18 es alta calidad."
        return ""
    }
    if {[catch {set molid [movie_molid_value]} err]} {
        msg error "Molecula invalida" $err
        return ""
    }
    set numframes [molinfo $molid get numframes]
    set start $movie_start
    set end $movie_end
    if {$end < 0} { set end [expr {$numframes - 1}] }
    if {$start < 0 || $start >= $numframes || $end < $start || $end >= $numframes} {
        msg error "Rango de frames invalido" "La molecula $molid contiene frames entre 0 y [expr {$numframes - 1}]."
        return ""
    }
    if {[catch {set resolution [validate_resolution {*}[get_resolution]]} err]} {
        msg error "Resolucion invalida" $err
        return ""
    }
    foreach {movie_width movie_height} $resolution { break }

    set specs [list]
    set sequence 1
    for {set frame $start} {$frame <= $end} {incr frame $movie_stride} {
        lappend specs [list $sequence $frame]
        incr sequence
    }
    if {[llength $specs] == 0} {
        msg error "Sin frames" "El rango seleccionado no produce frames para renderizar."
        return ""
    }
    if {[catch {set paths [movie_paths $movie_filename]} err]} {
        msg error "Archivo de pelicula invalido" $err
        return ""
    }
    set movie_output [dict get $paths output]
    set movie_temp_output [dict get $paths temp_output]
    set movie_dir [dict get $paths dir]
    set movie_worker [dict get $paths worker]
    set movie_manifest [dict get $paths manifest]
    set movie_lock [dict get $paths lock]
    if {[file exists $movie_output] && [file isdirectory $movie_output]} {
        msg error "Archivo MP4 invalido" "La ruta de salida es un directorio: $movie_output"
        return ""
    }
    set movie_active_molid $molid
    set movie_original_frame [molinfo $molid get frame]
    set captured_camera [blender_camera_snapshot]
    if {$movie_lock_camera} {
        set movie_camera $captured_camera
        set signature_camera $captured_camera
    } else {
        set movie_camera [dict create]
        # Cada frame registra su propia cámara; la inicial no debe bloquear resume.
        set signature_camera [dict create]
    }
    set movie_settings [blender_settings_snapshot]
    set movie_source_crc_cache [dict create]
    if {[catch {set movie_scene [movie_scene_snapshot $molid]} err]} {
        msg error "Escena VMD invalida" $err
        return ""
    }
    set movie_frame_specs $specs
    set movie_total [llength $specs]
    set movie_run_options [dict create \
        resume $movie_resume \
        keep_assets $movie_keep_assets \
        overwrite $movie_overwrite \
        fps $movie_fps \
        crf $movie_crf]
    set molecule_name [molinfo $molid get name]
    set molecule_atoms [molinfo $molid get numatoms]
    set movie_signature [movie_signature $molecule_name $molecule_atoms $numframes \
        $movie_frame_specs $movie_width $movie_height \
        [dict create lock_camera $movie_lock_camera camera $signature_camera] $movie_settings $movie_scene]
    if {[catch {file mkdir $movie_dir} err]} {
        msg error "No se pudo preparar la pelicula" "No se pudo crear $movie_dir: $err"
        return ""
    }
    if {[catch {movie_acquire_lock} err]} {
        msg error "Lote de pelicula ocupado" $err
        return ""
    }
    if {[file exists $movie_output]} {
        if {[file isdirectory $movie_output]} {
            movie_release_lock
            msg error "Archivo MP4 invalido" "La ruta de salida es un directorio: $movie_output"
            return ""
        }
        if {![dict get $movie_run_options overwrite]} {
            movie_release_lock
            msg error "MP4 existente" "Ya existe $movie_output. Activa 'Sobrescribir MP4 existente' o elige otro archivo."
            return ""
        }
    }
    if {[catch {movie_prepare_assets} err]} {
        movie_release_lock
        msg error "Assets de pelicula invalidos" $err
        return ""
    }
    catch {file delete -force $movie_temp_output}

    set movie_jobs [list]
    set movie_pending [list]
    set movie_index 0
    set movie_render_total 0
    set movie_worker_complete 0
    set movie_rendered_jobs [dict create]
    set movie_cancel_requested 0
    set movie_stage "export"
    set movie_pipe ""
    set movie_process_kind ""
    set movie_after ""
    set movie_cancel_after ""
    incr movie_run_id
    set movie_running 1
    set movie_progress 0
    set movie_progress_text "VMD: 0/$movie_total"
    set movie_status "Preparando $movie_total frame(s) de VMD para Blender; ajustes congelados para este lote."
    movie_update_controls
    log "=========================================="
    log "PELÍCULA Blender frames=$start..$end salto=$movie_stride fps=[dict get $movie_run_options fps] destino=$movie_output"
    log "Assets: $movie_dir | cámara [expr {$movie_lock_camera ? "bloqueada" : "por frame"}]"
    set movie_after [after 1 [list ::Render2K::movie_export_next]]
    return $movie_output
}

proc ::Render2K::render2k_movie {{molid "top"} {start 0} {end -1} {stride 1} {fps 30} {outname ""}} {
    variable movie_running
    variable movie_molid
    variable movie_start
    variable movie_end
    variable movie_stride
    variable movie_fps
    variable movie_filename
    if {$movie_running} { return [do_movie] }
    set movie_molid $molid
    set movie_start $start
    set movie_end $end
    set movie_stride $stride
    set movie_fps $fps
    if {$outname ne ""} { set movie_filename $outname }
    return [do_movie]
}

proc render2k_movie {args} {
    return [::Render2K::render2k_movie {*}$args]
}

# ----------------------------------------------------------------------------
# GUI
# ----------------------------------------------------------------------------

proc ::Render2K::close_window {} {
    variable w
    catch { cancel_movie }
    if {$w eq "" || [llength [info commands winfo]] == 0} { return }
    if {[catch {winfo exists $w} exists] || !$exists} {
        set w ""
        return
    }
    # VMD keeps the extension window registration, so hide it instead of
    # destroying it. The same window can then be restored from Extensions.
    catch { wm withdraw $w }
}

proc ::Render2K::show_tab {t} {
    variable w
    foreach tab {r l m v} {
        if {[winfo exists $w.main.$tab]} { pack forget $w.main.$tab }
    }
    pack $w.main.$t -fill both -expand 1 -padx 4 -pady 4
}

proc ::Render2K::choose_hdri {} {
    variable blender_hdri_path
    set types [list \
        [list "HDRI / OpenEXR" {.hdr .exr}] \
        [list "HDR Radiance" {.hdr}] \
        [list "OpenEXR" {.exr}] \
        [list "Todos los archivos" *]]
    set chosen [tk_getOpenFile -title "Seleccionar World Environment HDRI" -filetypes $types]
    if {$chosen ne ""} {
        set blender_hdri_path [file normalize $chosen]
    }
}

proc ::Render2K::clear_hdri {} {
    variable blender_hdri_path
    set blender_hdri_path ""
}

proc ::Render2K::lighting_preset {preset} {
    variable blender_light_multiplier
    variable blender_key_strength
    variable blender_fill_strength
    variable blender_rim_strength
    variable blender_sun_angle
    variable blender_ambient_strength
    variable blender_exposure
    switch -- $preset {
        bright {
            set blender_light_multiplier 1.0
            set blender_key_strength 4.0
            set blender_fill_strength 2.0
            set blender_rim_strength 2.5
            set blender_sun_angle 20.0
            set blender_ambient_strength 0.65
            set blender_exposure 0.35
        }
        soft {
            set blender_light_multiplier 1.0
            set blender_key_strength 3.2
            set blender_fill_strength 2.4
            set blender_rim_strength 1.8
            set blender_sun_angle 35.0
            set blender_ambient_strength 0.85
            set blender_exposure 0.20
        }
        contrast {
            set blender_light_multiplier 1.0
            set blender_key_strength 5.0
            set blender_fill_strength 1.2
            set blender_rim_strength 3.2
            set blender_sun_angle 12.0
            set blender_ambient_strength 0.40
            set blender_exposure 0.30
        }
    }
}

proc ::Render2K::update_background_controls {} {
    variable w
    variable blender_background_mode
    if {$w eq "" || [llength [info commands winfo]] == 0} { return }
    set l $w.main.l
    if {[catch {winfo exists $l.light} exists] || !$exists} { return }

    set ambient_state [expr {$blender_background_mode eq "flat" ? "normal" : "disabled"}]
    set world_state   [expr {$blender_background_mode eq "world" ? "normal" : "disabled"}]
    set hdri_state    [expr {$blender_background_mode eq "hdri" ? "normal" : "disabled"}]

    foreach widget [list $l.light.s2.amb $l.light.s4.world] state [list $ambient_state $world_state] {
        catch { $widget configure -state $state }
    }
    foreach widget [list $l.light.s4.hdri $l.light.s5.path $l.light.s5.open $l.light.s5.clear \
                         $l.light.s6.visible $l.light.s6.rot] {
        catch { $widget configure -state $hdri_state }
    }
}

proc ::Render2K::update_resolution_fields {} {
    variable w
    variable resolution_preset
    variable custom_width
    variable custom_height
    variable resolutions
    variable resolution_info
    if {![winfo exists $w]} { return }
    set r $w.main.r
    if {$resolution_preset eq "Custom"} {
        $r.res.custom.width configure -state normal
        $r.res.custom.height configure -state normal
        set resolution_info "Personalizada: ${custom_width} x ${custom_height} px"
    } else {
        $r.res.custom.width configure -state disabled
        $r.res.custom.height configure -state disabled
        set res $resolutions($resolution_preset)
        set resolution_info "Seleccionada: [lindex $res 0] x [lindex $res 1] px"
    }
}

proc ::Render2K::render2k_window {} {
    variable w
    variable resolution_preset
    variable bg_color
    variable engine

    detect_all
    set engine "blender"

    if {$w ne "" && ![catch {winfo exists $w} exists] && $exists} {
        catch { wm deiconify $w }
        catch { raise $w }
        catch { focus -force $w }
        return $w
    }
    set w ""
    if {[winfo exists .render2k]} { catch { destroy .render2k } }
    set w [toplevel .render2k]
    wm title $w "Blender Render (VMD) - v5.2"
    wm resizable $w 0 0
    wm protocol $w WM_DELETE_WINDOW ::Render2K::close_window

    label $w.title -text "Blender Render" -font {-weight bold -size 11}
    pack $w.title -pady 4

    label $w.status -justify left -font {-size 8} -anchor w -padx 8
    pack $w.status -fill x -pady 2
    set txt "Blender: [expr {$::Render2K::have_blender ne 0 ? "OK" : "no disponible"}]"
    append txt "  |  GPU: [expr {$::Render2K::gpu_name ne "" ? $::Render2K::gpu_name : "no detectada"}]"
    append txt "  |  FFmpeg: [expr {$::Render2K::have_ffmpeg ne 0 && $::Render2K::have_ffmpeg ne "" ? "OK" : "no disponible"}]"
    $w.status configure -text $txt \
        -fg [expr {$::Render2K::have_blender ne 0 ? "#006600" : "#aa0000"}]

    frame $w.bar
    pack $w.bar -fill x -padx 6
    button $w.bar.b1 -text "Renderizado" -width 14 -relief sunken -bg "#90caf9" \
        -command [list ::Render2K::show_tab r]
    button $w.bar.b2 -text "Iluminacion" -width 14 -relief raised -bg "#e0e0e0" \
        -command [list ::Render2K::show_tab l]
    button $w.bar.b3 -text "Materiales" -width 16 -relief raised -bg "#e0e0e0" \
        -command [list ::Render2K::show_tab m]
    button $w.bar.b4 -text "Pelicula Blender" -width 16 -relief raised -bg "#e0e0e0" \
        -command [list ::Render2K::show_tab v]
    pack $w.bar.b1 $w.bar.b2 $w.bar.b3 $w.bar.b4 -side left -padx 2 -pady 2 -expand 1 -fill x

    frame $w.main
    pack $w.main -fill both -expand 1 -padx 6 -pady 2
    frame $w.main.r
    frame $w.main.l
    frame $w.main.m
    frame $w.main.v

    # ===================== PESTANA RENDERIZADO =====================
    set r $w.main.r
    set l $w.main.l

    labelframe $r.eng -text "Motor Blender" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $r.eng -side top -fill x -pady 2
    frame $r.eng.row
    pack $r.eng.row -side top -fill x
    label $r.eng.row.l -text "Renderizador:" -font {-size 9} -width 13 -anchor w
    radiobutton $r.eng.row.cycles -text "Cycles" -font {-size 9} \
        -variable ::Render2K::blender_render_engine -value CYCLES
    radiobutton $r.eng.row.eevee -text "Eevee" -font {-size 9} \
        -variable ::Render2K::blender_render_engine -value EEVEE
    pack $r.eng.row.l -side left -padx 4
    pack $r.eng.row.cycles $r.eng.row.eevee -side left -padx 6
    label $r.eng.info -text "Cycles usa GPU cuando esta disponible; Eevee prioriza velocidad." \
        -font {-size 8} -anchor w -fg "#555555"
    pack $r.eng.info -side top -anchor w -padx 4 -pady 1

    labelframe $r.bl -text "Opciones Blender" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $r.bl -side top -fill x -pady 2
    frame $r.bl.s1; pack $r.bl.s1 -side top -fill x
    label $r.bl.s1.l -text "Samples:" -font {-size 9} -width 12 -anchor w
    spinbox $r.bl.s1.s -from 16 -to 2048 -increment 16 -width 7 \
        -textvariable ::Render2K::blender_samples -font {-size 9}
    checkbutton $r.bl.s1.d -text "Denoise (Cycles)" -font {-size 9} \
        -variable ::Render2K::blender_denoise
    pack $r.bl.s1.l -side left -padx 4
    pack $r.bl.s1.s -side left -padx 2
    pack $r.bl.s1.d -side left -padx 12
    frame $r.bl.s2; pack $r.bl.s2 -side top -fill x
    checkbutton $r.bl.s2.a -text "Auto-render en Blender" \
        -font {-size 9} -variable ::Render2K::blender_autorun
    checkbutton $r.bl.s2.o -text "Match orientacion VMD" -font {-size 9} \
        -variable ::Render2K::blender_rotate
    pack $r.bl.s2.a -side left -padx 4
    pack $r.bl.s2.o -side left -padx 12

    labelframe $l.light -text "Iluminacion y fondo" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $l.light -side top -fill x -pady 2

    frame $l.light.s0; pack $l.light.s0 -side top -fill x -pady 1
    label $l.light.s0.l -text "Preset:" -font {-size 9} -width 12 -anchor w
    button $l.light.s0.b1 -text "Estudio claro" -font {-size 8} -command {::Render2K::lighting_preset bright}
    button $l.light.s0.b2 -text "Suave" -font {-size 8} -command {::Render2K::lighting_preset soft}
    button $l.light.s0.b3 -text "Contraste" -font {-size 8} -command {::Render2K::lighting_preset contrast}
    label $l.light.s0.el -text "Exposicion:" -font {-size 9}
    spinbox $l.light.s0.exp -from -5.0 -to 5.0 -increment 0.05 -width 6 \
        -textvariable ::Render2K::blender_exposure -font {-size 9}
    pack $l.light.s0.l $l.light.s0.b1 $l.light.s0.b2 $l.light.s0.b3 -side left -padx {4 2}
    pack $l.light.s0.exp $l.light.s0.el -side right -padx {2 4}

    frame $l.light.s1; pack $l.light.s1 -side top -fill x -pady 1
    label $l.light.s1.l -text "Luces estudio:" -font {-size 9} -width 12 -anchor w
    label $l.light.s1.kl -text "Key" -font {-size 8}
    spinbox $l.light.s1.key -from 0.0 -to 20.0 -increment 0.1 -width 5 \
        -textvariable ::Render2K::blender_key_strength -font {-size 9}
    label $l.light.s1.fl -text "Fill" -font {-size 8}
    spinbox $l.light.s1.fill -from 0.0 -to 20.0 -increment 0.1 -width 5 \
        -textvariable ::Render2K::blender_fill_strength -font {-size 9}
    label $l.light.s1.rl -text "Rim" -font {-size 8}
    spinbox $l.light.s1.rim -from 0.0 -to 20.0 -increment 0.1 -width 5 \
        -textvariable ::Render2K::blender_rim_strength -font {-size 9}
    label $l.light.s1.ml -text "Global" -font {-size 8}
    spinbox $l.light.s1.mul -from 0.0 -to 5.0 -increment 0.05 -width 5 \
        -textvariable ::Render2K::blender_light_multiplier -font {-size 9}
    pack $l.light.s1.l $l.light.s1.kl $l.light.s1.key $l.light.s1.fl $l.light.s1.fill \
         $l.light.s1.rl $l.light.s1.rim $l.light.s1.ml $l.light.s1.mul -side left -padx {4 2}

    frame $l.light.s2; pack $l.light.s2 -side top -fill x -pady 1
    label $l.light.s2.l -text "Ambiente:" -font {-size 9} -width 12 -anchor w
    scale $l.light.s2.amb -from 0.0 -to 3.0 -resolution 0.05 -orient horizontal -font {-size 8} \
        -variable ::Render2K::blender_ambient_strength -length 150 -showvalue 1
    label $l.light.s2.al -text "Suavidad SUN:" -font {-size 8}
    spinbox $l.light.s2.angle -from 0.1 -to 90.0 -increment 1.0 -width 6 \
        -textvariable ::Render2K::blender_sun_angle -font {-size 9}
    label $l.light.s2.deg -text "deg" -font {-size 8}
    pack $l.light.s2.l $l.light.s2.amb $l.light.s2.al $l.light.s2.angle $l.light.s2.deg \
        -side left -padx {4 2}

    frame $l.light.s3; pack $l.light.s3 -side top -fill x -pady 1
    label $l.light.s3.l -text "Fondo:" -font {-size 9} -width 12 -anchor w
    tk_optionMenu $l.light.s3.color ::Render2K::bg_color white black "8" current
    radiobutton $l.light.s3.flat -text "Plano" -font {-size 9} \
        -variable ::Render2K::blender_background_mode -value flat \
        -command ::Render2K::update_background_controls
    radiobutton $l.light.s3.world -text "World color" -font {-size 9} \
        -variable ::Render2K::blender_background_mode -value world \
        -command ::Render2K::update_background_controls
    radiobutton $l.light.s3.hdri -text "HDRI" -font {-size 9} \
        -variable ::Render2K::blender_background_mode -value hdri \
        -command ::Render2K::update_background_controls
    pack $l.light.s3.l $l.light.s3.color $l.light.s3.flat $l.light.s3.world $l.light.s3.hdri \
        -side left -padx {4 3}

    frame $l.light.s4; pack $l.light.s4 -side top -fill x -pady 1
    label $l.light.s4.l -text "Potencias:" -font {-size 9} -width 12 -anchor w
    label $l.light.s4.wl -text "World" -font {-size 8}
    scale $l.light.s4.world -from 0.0 -to 10.0 -resolution 0.05 -orient horizontal -font {-size 8} \
        -variable ::Render2K::blender_bg_strength -length 115 -showvalue 1
    label $l.light.s4.hl -text "HDRI" -font {-size 8}
    scale $l.light.s4.hdri -from 0.0 -to 10.0 -resolution 0.05 -orient horizontal -font {-size 8} \
        -variable ::Render2K::blender_hdri_strength -length 115 -showvalue 1
    pack $l.light.s4.l $l.light.s4.wl $l.light.s4.world $l.light.s4.hl $l.light.s4.hdri \
        -side left -padx {4 2}

    frame $l.light.s5; pack $l.light.s5 -side top -fill x -pady 1
    label $l.light.s5.l -text "HDRI:" -font {-size 9} -width 12 -anchor w
    entry $l.light.s5.path -textvariable ::Render2K::blender_hdri_path -font {-size 8} -width 40
    button $l.light.s5.open -text "Abrir..." -font {-size 8} -command ::Render2K::choose_hdri
    button $l.light.s5.clear -text "X" -font {-size 8} -command ::Render2K::clear_hdri
    pack $l.light.s5.l -side left -padx 4
    pack $l.light.s5.path -side left -padx 2 -fill x -expand 1
    pack $l.light.s5.open $l.light.s5.clear -side left -padx 2

    frame $l.light.s6; pack $l.light.s6 -side top -fill x -pady 1
    label $l.light.s6.l -text "HDRI vista:" -font {-size 9} -width 12 -anchor w
    checkbutton $l.light.s6.visible -text "Mostrar HDRI en el fondo" -font {-size 8} \
        -variable ::Render2K::blender_hdri_visible
    label $l.light.s6.rl -text "Rotacion:" -font {-size 8}
    spinbox $l.light.s6.rot -from -360.0 -to 360.0 -increment 5.0 -width 7 \
        -textvariable ::Render2K::blender_hdri_rotation -font {-size 9}
    label $l.light.s6.deg -text "deg" -font {-size 8}
    pack $l.light.s6.l $l.light.s6.visible $l.light.s6.rl $l.light.s6.rot $l.light.s6.deg \
        -side left -padx {4 2}

    label $l.light.note -text "Recomendado: color blanco + modo Plano + Estudio claro. El fondo queda blanco, pero el modelo recibe luz ambiente y las tres luces de estudio. HDRI puede iluminar/reflejar manteniendo el fondo blanco si 'Mostrar HDRI' esta desactivado." \
        -font {-size 8} -anchor w -justify left -fg "#555555" -wraplength 520
    pack $l.light.note -side top -anchor w -padx 4 -pady {2 1}

    labelframe $r.res -text "Resolucion" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $r.res -side top -fill x -pady 2
    frame $r.res.presets
    pack $r.res.presets -side top -fill x -pady 1
    set row 0; set col 0
    foreach preset {HD\ \(1280x720\) Full\ HD\ \(1920x1080\) 2K\ \(2560x1440\) \
                    4K\ \(3840x2160\) 5K\ \(5120x2880\) 8K\ \(7680x4320\) Custom} {
        radiobutton $r.res.presets.r$row$col -text [string map {\( ( \) )} $preset] \
            -font {-size 9} -variable ::Render2K::resolution_preset \
            -value [string map {\( ( \) )} $preset] \
            -command ::Render2K::update_resolution_fields
        grid $r.res.presets.r$row$col -row $row -column $col -sticky w -padx 4
        incr col
        if {$col > 3} { set col 0; incr row }
    }
    frame $r.res.custom
    pack $r.res.custom -side top -fill x -pady 1
    label $r.res.custom.w -text "Ancho:" -font {-size 9}
    entry $r.res.custom.width -textvariable ::Render2K::custom_width -width 7 -font {-size 9} -state disabled
    label $r.res.custom.h -text "Alto:" -font {-size 9}
    entry $r.res.custom.height -textvariable ::Render2K::custom_height -width 7 -font {-size 9} -state disabled
    label $r.res.custom.px -text "px" -font {-size 9}
    pack $r.res.custom.w -side left -padx {8 2}
    pack $r.res.custom.width -side left -padx 2
    pack $r.res.custom.h -side left -padx {8 2}
    pack $r.res.custom.height -side left -padx 2
    pack $r.res.custom.px -side left -padx 4

    labelframe $r.file -text "Archivo de salida" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $r.file -side top -fill x -pady 2
    frame $r.file.f1; pack $r.file.f1 -side top -fill x -pady 1
    label $r.file.f1.l -text "Nombre:" -width 10 -anchor w -font {-size 9}
    entry $r.file.f1.e -textvariable ::Render2K::filename -font {-size 9}
    pack $r.file.f1.l -side left -padx 4
    pack $r.file.f1.e -side left -padx 4 -fill x -expand 1
    frame $r.file.f2; pack $r.file.f2 -side top -fill x -pady 1
    label $r.file.f2.l -text "Formato:" -width 10 -anchor w -font {-size 9}
    pack $r.file.f2.l -side left -padx 4
    foreach fmt {png jpg tiff bmp} {
        radiobutton $r.file.f2.$fmt -text [string toupper $fmt] -font {-size 9} \
            -variable ::Render2K::file_format -value $fmt
        pack $r.file.f2.$fmt -side left -padx 4
    }

    # ====================== PESTANA PELICULA ========================
    set v $w.main.v
    label $v.info -text "Renderiza una trayectoria de VMD con el mismo pipeline Blender de la imagen fija.\nVMD exporta cada frame; Blender los procesa en un único lote; FFmpeg crea el MP4. Los cambios durante la ejecución se aplican al siguiente lote." \
        -anchor w -font {-size 8} -justify left -fg "#555555"
    pack $v.info -side top -anchor w -padx 4 -pady 4

    labelframe $v.frames -text "Frames de VMD" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $v.frames -side top -fill x -pady 2
    frame $v.frames.r1; pack $v.frames.r1 -side top -fill x -pady 1
    label $v.frames.r1.ml -text "Molécula:" -font {-size 9} -width 11 -anchor w
    entry $v.frames.r1.m -textvariable ::Render2K::movie_molid -width 8 -font {-size 9}
    label $v.frames.r1.sl -text "Inicio:" -font {-size 9}
    entry $v.frames.r1.s -textvariable ::Render2K::movie_start -width 7 -font {-size 9}
    label $v.frames.r1.el -text "Final:" -font {-size 9}
    entry $v.frames.r1.e -textvariable ::Render2K::movie_end -width 7 -font {-size 9}
    pack $v.frames.r1.ml $v.frames.r1.m -side left -padx {4 2}
    pack $v.frames.r1.sl $v.frames.r1.s -side left -padx {10 2}
    pack $v.frames.r1.el $v.frames.r1.e -side left -padx {10 2}
    frame $v.frames.r2; pack $v.frames.r2 -side top -fill x -pady 1
    label $v.frames.r2.jl -text "Cada:" -font {-size 9} -width 11 -anchor w
    entry $v.frames.r2.j -textvariable ::Render2K::movie_stride -width 7 -font {-size 9}
    label $v.frames.r2.jt -text "frame(s)   Final=-1 usa el último frame." -font {-size 8} -fg "#555555"
    checkbutton $v.frames.r2.cam -text "Bloquear cámara VMD" -font {-size 9} \
        -variable ::Render2K::movie_lock_camera
    pack $v.frames.r2.jl $v.frames.r2.j $v.frames.r2.jt -side left -padx {4 2}
    pack $v.frames.r2.cam -side right -padx 4

    labelframe $v.out -text "MP4 y calidad" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $v.out -side top -fill x -pady 2
    frame $v.out.r1; pack $v.out.r1 -side top -fill x -pady 1
    label $v.out.r1.l -text "Archivo MP4:" -font {-size 9} -width 11 -anchor w
    entry $v.out.r1.e -textvariable ::Render2K::movie_filename -font {-size 9}
    pack $v.out.r1.l -side left -padx 4
    pack $v.out.r1.e -side left -padx 2 -fill x -expand 1
    frame $v.out.r2; pack $v.out.r2 -side top -fill x -pady 1
    label $v.out.r2.fl -text "FPS:" -font {-size 9} -width 11 -anchor w
    spinbox $v.out.r2.f -from 1 -to 240 -increment 1 -width 7 \
        -textvariable ::Render2K::movie_fps -font {-size 9}
    label $v.out.r2.cl -text "CRF H.264:" -font {-size 9}
    spinbox $v.out.r2.c -from 0 -to 51 -increment 1 -width 7 \
        -textvariable ::Render2K::movie_crf -font {-size 9}
    label $v.out.r2.note -text "18 = alta calidad" -font {-size 8} -fg "#555555"
    pack $v.out.r2.fl $v.out.r2.f -side left -padx {4 2}
    pack $v.out.r2.cl $v.out.r2.c -side left -padx {12 2}
    pack $v.out.r2.note -side left -padx 4

    labelframe $v.assets -text "Lote reanudable" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $v.assets -side top -fill x -pady 2
    checkbutton $v.assets.resume -text "Reanudar assets verificados del mismo lote" -font {-size 9} \
        -variable ::Render2K::movie_resume
    checkbutton $v.assets.keep -text "Conservar OBJ, MTL, scripts y PNG al terminar" -font {-size 9} \
        -variable ::Render2K::movie_keep_assets
    checkbutton $v.assets.overwrite -text "Sobrescribir MP4 existente al finalizar" -font {-size 9} \
        -variable ::Render2K::movie_overwrite
    pack $v.assets.resume $v.assets.keep $v.assets.overwrite -side top -anchor w -padx 4 -pady 1

    labelframe $v.progress -text "Estado" -font {-weight bold -size 9} -padx 6 -pady 4
    pack $v.progress -side top -fill x -pady 2
    scale $v.progress.bar -from 0 -to 100 -resolution 1 -orient horizontal -showvalue 0 \
        -length 420 -variable ::Render2K::movie_progress -state disabled
    label $v.progress.count -textvariable ::Render2K::movie_progress_text -font {-size 8} -anchor w
    label $v.progress.status -textvariable ::Render2K::movie_status -font {-size 8} -anchor w \
        -justify left -wraplength 440
    pack $v.progress.bar -side top -fill x -padx 4
    pack $v.progress.count $v.progress.status -side top -fill x -padx 4 -pady 1
    frame $v.actions; pack $v.actions -side top -pady 6
    button $v.actions.start -text "RENDERIZAR PELÍCULA" -command ::Render2K::do_movie \
        -bg "#1565c0" -fg white -padx 16 -pady 5 -font {-weight bold -size 10}
    button $v.actions.cancel -text "Cancelar" -command ::Render2K::cancel_movie \
        -padx 14 -pady 5 -font {-size 9}
    pack $v.actions.start $v.actions.cancel -side left -padx 6

    # =================== PESTANA MATERIALES BLENDER ==================
    set m $w.main.m

    label $m.info -text "VMD solo selecciona el perfil y aporta el color de la geometria.\nLos parametros siguientes se aplican al Principled BSDF de Blender." \
        -anchor w -font {-size 8} -justify left -fg "#555555"
    pack $m.info -side top -anchor w -padx 4 -pady 4

    labelframe $m.profile -text "Perfil Blender asociado al material VMD" \
        -font {-weight bold -size 9} -padx 6 -pady 4
    pack $m.profile -side top -fill x -pady 2
    frame $m.profile.row
    pack $m.profile.row -side top -fill x
    label $m.profile.row.l -text "Perfil:" -font {-size 9} -width 12 -anchor w
    menubutton $m.profile.row.select -textvariable ::Render2K::blender_mat_selected \
        -menu $m.profile.row.select.menu -relief raised -width 20 -anchor w
    menu $m.profile.row.select.menu -tearoff 0
    foreach key [blender_material_keys] {
        $m.profile.row.select.menu add command -label $key \
            -command [list ::Render2K::select_blender_material $key]
    }
    button $m.profile.row.save -text "Guardar ajustes" -font {-size 9} \
        -command ::Render2K::save_blender_material
    pack $m.profile.row.l -side left -padx 4
    pack $m.profile.row.select -side left -padx 4
    pack $m.profile.row.save -side left -padx 8

    labelframe $m.params -text "Parametros Principled BSDF" \
        -font {-weight bold -size 9} -padx 6 -pady 4
    pack $m.params -side top -fill x -pady 4
    set material_fields [list \
        [list roughness "Rugosidad" 0.0 1.0 0.01] \
        [list metallic "Metallic" 0.0 1.0 0.01] \
        [list specular "Nivel especular" 0.0 1.0 0.01] \
        [list alpha "Alpha" 0.0 1.0 0.01] \
        [list transmission "Transmision (vidrio)" 0.0 1.0 0.01] \
        [list ior "IOR" 1.0 3.0 0.01]]
    set row 0
    foreach field $material_fields {
        foreach {name label low high step} $field { break }
        label $m.params.l$row -text "$label:" -font {-size 9} -width 18 -anchor w
        spinbox $m.params.s$row -from $low -to $high -increment $step -width 8 \
            -textvariable ::Render2K::blender_mat_$name -font {-size 9}
        label $m.params.r$row -text "$low - $high" -font {-size 8} -anchor w
        grid $m.params.l$row -row $row -column 0 -sticky w -padx 4 -pady 1
        grid $m.params.s$row -row $row -column 1 -sticky w -padx 4 -pady 1
        grid $m.params.r$row -row $row -column 2 -sticky w -padx 4 -pady 1
        incr row
    }

    label $m.note -text "Alpha produce transparencia clara; Transmision produce vidrio fisico y requiere Alpha=1.\nNivel especular usa Specular en Blender 3.x y Specular IOR Level en Blender 4.x." \
        -anchor w -font {-size 8} -justify left -fg "#555555" -wraplength 440
    pack $m.note -side top -anchor w -padx 6 -pady {0 2}
    label $m.status -textvariable ::Render2K::blender_mat_status \
        -anchor w -font {-size 8} -justify left -fg "#006600" -wraplength 440
    pack $m.status -side top -fill x -padx 6 -pady {0 4}
    load_blender_material

    # ===================== BOTONES / PIE =====================
    frame $w.act
    pack $w.act -side top -pady 4
    button $w.act.render -text "RENDERIZAR IMAGEN" -command {::Render2K::do_render} \
        -bg "#4CAF50" -fg white -padx 24 -pady 6 -font {-weight bold -size 11}
    button $w.act.close -text "Cerrar" -command ::Render2K::close_window \
        -padx 16 -pady 6 -font {-size 9}
    pack $w.act.render -side left -padx 6
    pack $w.act.close -side left -padx 6

    update_background_controls
    update_resolution_fields
    movie_update_controls
    show_tab r
}

proc render2k_tk {} {
    ::Render2K::render2k_window
    return $::Render2K::w
}

vmd_install_extension render2k render2k_tk "Rendering/Blender Render"

::Render2K::detect_all
puts "=========================================="
puts "Blender Render v5.2 cargado"
puts "Acceso: Extensions -> Rendering -> Blender Render"
puts "=========================================="